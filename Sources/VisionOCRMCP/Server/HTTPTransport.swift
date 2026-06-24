import Foundation
import HTTPTypes
import Hummingbird
import Logging
import MCP
import NIOCore

struct RequestRecord: Codable, Sendable {
    let id: Int
    let tool: String
    let timestamp: String
    let durationMs: Int
    let success: Bool
}

actor RequestHistoryStore {
    private var records: [RequestRecord] = []

    func append(_ record: RequestRecord) {
        records.append(record)
        if records.count > 1000 {
            records.removeFirst(records.count - 1000)
        }
    }

    func getRecords(limit: Int = 100) -> [RequestRecord] {
        Array(records.suffix(limit))
    }

    func getMetrics() -> (total: Int, success: Int, failed: Int, avgMs: Int) {
        let total = records.count
        let success = records.filter(\.success).count
        let failed = total - success
        let avgMs = total > 0 ? records.map(\.durationMs).reduce(0, +) / total : 0
        return (total, success, failed, avgMs)
    }

    var count: Int { records.count }
}

actor RateLimiter {
    private var requestTimestamps: [String: [Date]] = [:]
    private let limit: Int

    init(limit: Int) {
        self.limit = limit
    }

    func isAllowed(for key: String) -> Bool {
        let now = Date()
        let windowStart = now.addingTimeInterval(-60)
        var timestamps = requestTimestamps[key, default: []]
        timestamps = timestamps.filter { $0 > windowStart }
        if timestamps.count >= limit {
            return false
        }
        timestamps.append(now)
        requestTimestamps[key] = timestamps
        return true
    }
}

private struct FixedSessionIDGenerator: SessionIDGenerator {
    let sessionID: String
    func generateSessionID() -> String { sessionID }
}

actor MCPSessionManager {
    struct SessionContext {
        let server: Server
        let transport: StatefulHTTPServerTransport
        let createdAt: Date
        var lastAccessedAt: Date
    }

    private let config: ServerConfig
    private let validationPipeline: any HTTPRequestValidationPipeline
    private let logger: Logger
    private var sessions: [String: SessionContext] = [:]

    private var statelessServer: Server?
    private var statelessTransport: StatelessHTTPServerTransport?

    init(config: ServerConfig, validationPipeline: any HTTPRequestValidationPipeline, logger: Logger) {
        self.config = config
        self.validationPipeline = validationPipeline
        self.logger = logger
    }

    func handleStatefulRequest(_ request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
        let sessionID = request.header(HTTPHeaderName.sessionID)

        if let sessionID, var session = sessions[sessionID] {
            session.lastAccessedAt = Date()
            sessions[sessionID] = session

            let response = await session.transport.handleRequest(request)

            if request.method.uppercased() == "DELETE" && response.statusCode == 200 {
                sessions.removeValue(forKey: sessionID)
            }

            return response
        }

        if request.method.uppercased() == "POST",
           let body = request.body,
           isInitializeRequest(body) {
            return await createSessionAndHandle(request)
        }

        if sessionID != nil {
            return .error(statusCode: 404, .invalidRequest("Not Found: Session not found or expired"))
        }
        return .error(
            statusCode: 400,
            .invalidRequest("Bad Request: Missing \(HTTPHeaderName.sessionID) header")
        )
    }

    func handleStatelessRequest(_ request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
        if statelessTransport == nil {
            let slPipeline = StandardValidationPipeline(validators: [
                OriginValidator.disabled,
                ContentTypeValidator(),
            ])
            let transport = StatelessHTTPServerTransport(
                validationPipeline: slPipeline,
                logger: logger
            )
            let server = Server(
                name: "vision-ocr-mcp",
                version: "0.9.0",
                capabilities: .init(tools: .init(listChanged: false))
            )
            let toolRegistry = ToolRegistry()
            await toolRegistry.registerTools(on: server)
            do {
                try await server.start(transport: transport)
                self.statelessServer = server
                self.statelessTransport = transport
            } catch {
                return .error(statusCode: 500, .internalError("Stateless init failed: \(error.localizedDescription)"))
            }
        }
        return await statelessTransport!.handleRequest(request)
    }

    private func createSessionAndHandle(_ request: MCP.HTTPRequest) async -> MCP.HTTPResponse {
        let sessionID = UUID().uuidString

        let transport = StatefulHTTPServerTransport(
            sessionIDGenerator: FixedSessionIDGenerator(sessionID: sessionID),
            validationPipeline: validationPipeline,
            logger: logger
        )

        let server = Server(
            name: "vision-ocr-mcp",
            version: "0.9.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        let toolRegistry = ToolRegistry()
        await toolRegistry.registerTools(on: server)

        do {
            try await server.start(transport: transport)

            sessions[sessionID] = SessionContext(
                server: server,
                transport: transport,
                createdAt: Date(),
                lastAccessedAt: Date()
            )

            let response = await transport.handleRequest(request)

            if case .error = response {
                sessions.removeValue(forKey: sessionID)
                await transport.disconnect()
            }

            return response
        } catch {
            await transport.disconnect()
            return .error(
                statusCode: 500,
                .internalError("Failed to create session: \(error.localizedDescription)")
            )
        }
    }

    private func isInitializeRequest(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let method = json["method"] as? String else { return false }
        return method == "initialize"
    }

    func cleanupExpired(timeout: TimeInterval = 3600) async {
        let now = Date()
        let expired = sessions.filter { now.timeIntervalSince($0.value.lastAccessedAt) > timeout }
        for (sessionID, session) in expired {
            await session.transport.disconnect()
            sessions.removeValue(forKey: sessionID)
            logger.info("Session expired", metadata: ["sessionID": "\(sessionID)"])
        }
    }

    func wantsStateful(_ headers: [String: String]) -> Bool {
        let accept = headers["accept"] ?? headers["Accept"] ?? ""
        return accept.contains("text/event-stream")
    }
}

final class HTTPTransportBridge: Sendable {
    let config: ServerConfig
    let sessionManager: MCPSessionManager
    let logger: Logger
    let historyStore = RequestHistoryStore()
    let rateLimiter: RateLimiter
    let startTime = Date()

    init(config: ServerConfig, sessionManager: MCPSessionManager, logger: Logger) {
        self.config = config
        self.sessionManager = sessionManager
        self.logger = logger
        self.rateLimiter = RateLimiter(limit: config.rateLimitPerMinute)
    }

    func start() async throws {
        let router = Router()

        router.on("/mcp", method: .options) { [self] request, _ -> Response in
            var headers = self.corsHeaders(for: request)
            headers[.contentType] = "text/plain"
            return Response(status: .ok, headers: headers, body: .init(byteBuffer: .init(string: "")))
        }

        router.post("/mcp") { request, _ -> Response in
            return try await self.handleMCPPost(request: request)
        }

        router.get("/mcp") { request, _ -> Response in
            return try await self.handleMCPGet(request: request)
        }

        router.delete("/mcp") { request, _ -> Response in
            return try await self.handleMCPDelete(request: request)
        }

        router.get("/health") { _, _ -> Response in
            let body = #"{"status":"ok","version":"0.9.0"}"#
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: body))
            )
        }

        if config.enableUI {
            router.get("/ui") { _, _ -> Response in
                Response(
                    status: .ok,
                    headers: [.contentType: "text/html; charset=utf-8"],
                    body: .init(byteBuffer: .init(string: self.uiHTML()))
                )
            }

            router.get("/api/status") { _, _ -> Response in
                let uptime = Int(Date().timeIntervalSince(self.startTime))
                let hours = uptime / 3600
                let minutes = (uptime % 3600) / 60
                let seconds = uptime % 60
                let uptimeStr = String(format: "%02d:%02d:%02d", hours, minutes, seconds)
                let memoryMB = self.getMemoryUsageMB()
                let status = """
                {"running":true,"transport":"http (stateful+stateless)","port":\(self.config.port),"uptime":"\(uptimeStr)","memoryMB":\(memoryMB),"version":"0.9.0"}
                """
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: .init(string: status))
                )
            }

            router.get("/api/history") { _, _ -> Response in
                let records = await self.historyStore.getRecords()
                let encoder = JSONEncoder()
                encoder.outputFormatting = .prettyPrinted
                let data = (try? encoder.encode(records)) ?? Data("[]".utf8)
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: .init(data: data))
                )
            }

            router.get("/api/metrics") { _, _ -> Response in
                let m = await self.historyStore.getMetrics()
                let total = m.total
                let success = m.success
                let failed = m.failed
                let avgMs = m.avgMs
                let uptime = Int(Date().timeIntervalSince(self.startTime))
                let metrics = """
                {"totalRequests":\(total),"successCount":\(success),"failedCount":\(failed),"avgDurationMs":\(avgMs),"uptimeSeconds":\(uptime)}
                """
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: .init(string: metrics))
                )
            }

            router.get("/api/config") { _, _ -> Response in
                let hasKey = self.config.resolvedApiKey != nil
                let keySource = self.config.apiKey != nil ? "cli-flag" : (ProcessInfo.processInfo.environment["VISION_OCR_MCP_API_KEY"] != nil ? "env-var" : "none")
                let configJson = """
                {"transport":"http","host":"\(self.config.host)","port":\(self.config.port),"enableUI":\(self.config.enableUI),"rateLimitPerMinute":\(self.config.rateLimitPerMinute),"logLevel":"\(self.config.logLevel)","hasApiKey":\(hasKey),"apiKeySource":"\(keySource)"}
                """
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: .init(string: configJson))
                )
            }
        }

        Task {
            while true {
                try? await Task.sleep(for: .seconds(60))
                await sessionManager.cleanupExpired()
            }
        }

        let app = Application(
            router: router,
            configuration: .init(
                address: .hostname(config.host, port: config.port)
            ),
            logger: logger
        )

        logger.info("HTTP server starting on \(config.host):\(config.port)")
        try await app.run()
    }

    private func getMemoryUsageMB() -> Int {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.resident_size / (1024 * 1024)) : 0
    }

    private func corsHeaders(for request: Request) -> HTTPFields {
        var headers = HTTPFields()
        if let origin = request.headers[.init("origin")!] {
            if config.allowedOrigins.isEmpty || config.allowedOrigins.contains(origin) || config.allowedOrigins.contains("*") {
                headers[.init("access-control-allow-origin")!] = origin
                headers[.init("access-control-allow-methods")!] = "GET, POST, DELETE, OPTIONS"
                headers[.init("access-control-allow-headers")!] = "Content-Type, Authorization, Accept, Mcp-Session-Id, Last-Event-ID"
                headers[.init("access-control-expose-headers")!] = "Mcp-Session-Id"
                headers[.init("access-control-max-age")!] = "86400"
            }
        }
        return headers
    }

    func recordRequest(tool: String, durationMs: Int, success: Bool) async {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        let id = await historyStore.count + 1
        let record = RequestRecord(
            id: id,
            tool: tool,
            timestamp: formatter.string(from: Date()),
            durationMs: durationMs,
            success: success
        )
        await historyStore.append(record)
    }

    private func buildMCPRequest(from request: Request, body: Data) -> MCP.HTTPRequest {
        var headers: [String: String] = [:]
        for field in request.headers {
            headers[String(field.name)] = String(field.value)
        }
        return MCP.HTTPRequest(method: "POST", headers: headers, body: body, path: "/mcp")
    }

    private func buildMCPRequestForMethod(_ method: String, request: Request) -> MCP.HTTPRequest {
        var headers: [String: String] = [:]
        for field in request.headers {
            headers[String(field.name)] = String(field.value)
        }
        return MCP.HTTPRequest(method: method, headers: headers, body: nil, path: "/mcp")
    }

    private func checkAuth(headers: [String: String], cors: HTTPFields) -> Response? {
        guard let apiKey = config.resolvedApiKey else { return nil }
        guard let auth = headers["authorization"] ?? headers["Authorization"],
              auth.hasPrefix("Bearer "),
              String(auth.dropFirst(7)) == apiKey else {
            var rh: HTTPFields = [.contentType: "application/json"]
            for field in cors { rh[field.name] = field.value }
            return Response(
                status: .unauthorized,
                headers: rh,
                body: .init(byteBuffer: .init(string: #"{"error":"unauthorized","message":"Bearer token required."}"#))
            )
        }
        return nil
    }

    private func handleMCPPost(request: Request) async throws -> Response {
        let startTime = DispatchTime.now()
        let cors = corsHeaders(for: request)
        let bodyBytes = try await request.body.collect(upTo: 10 * 1024 * 1024)
        guard let bodyData = bodyBytes.getData(at: 0, length: bodyBytes.readableBytes) else {
            return Response(status: .badRequest, body: .init(byteBuffer: .init(string: "Empty body")))
        }

        var headers: [String: String] = [:]
        for field in request.headers {
            headers[String(field.name)] = String(field.value)
        }

        let accept = headers["accept"] ?? headers["Accept"] ?? "none"
        let bodyPreview = String(data: bodyData.prefix(200), encoding: .utf8) ?? "binary"
        let useStatefulLog = accept.contains("text/event-stream") ? "stateful" : "stateless"
        logger.info("POST /mcp accept=\(accept) mode=\(useStatefulLog) body=\(bodyPreview)")

        if let authResp = checkAuth(headers: headers, cors: cors) { return authResp }

        let clientIP = headers["x-forwarded-for"] ?? headers["x-real-ip"] ?? "default"
        let allowed = await rateLimiter.isAllowed(for: clientIP)
        if !allowed {
            var rh: HTTPFields = [.contentType: "application/json"]
            for field in cors { rh[field.name] = field.value }
            return Response(
                status: .tooManyRequests,
                headers: rh,
                body: .init(byteBuffer: .init(string: "{\"error\":\"rate_limit_exceeded\",\"message\":\"Rate limit: \(config.rateLimitPerMinute) requests/minute\"}"))
            )
        }

        let mcpRequest = MCP.HTTPRequest(method: "POST", headers: headers, body: bodyData, path: "/mcp")

        let useStateful = await sessionManager.wantsStateful(headers)
        let mcpResponse: MCP.HTTPResponse
        if useStateful {
            mcpResponse = await sessionManager.handleStatefulRequest(mcpRequest)
        } else {
            mcpResponse = await sessionManager.handleStatelessRequest(mcpRequest)
        }

        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000)
        var toolName = "unknown"
        if let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any],
           let method = json["method"] as? String {
            if method == "tools/call",
               let params = json["params"] as? [String: Any],
               let name = params["name"] as? String {
                toolName = name
            } else {
                toolName = method
            }
        }

        return buildHummingbirdResponse(from: mcpResponse, cors: cors, toolName: toolName, elapsed: elapsed)
    }

    private func handleMCPGet(request: Request) async throws -> Response {
        let cors = corsHeaders(for: request)
        var headers: [String: String] = [:]
        for field in request.headers {
            headers[String(field.name)] = String(field.value)
        }
        logger.info("GET /mcp session=\(headers["mcp-session-id"] ?? headers["Mcp-Session-Id"] ?? "none")")
        if let authResp = checkAuth(headers: headers, cors: cors) { return authResp }

        let mcpRequest = MCP.HTTPRequest(method: "GET", headers: headers, body: nil, path: "/mcp")
        let mcpResponse = await sessionManager.handleStatefulRequest(mcpRequest)

        return buildHummingbirdResponse(from: mcpResponse, cors: cors, toolName: "GET", elapsed: 0)
    }

    private func handleMCPDelete(request: Request) async throws -> Response {
        let cors = corsHeaders(for: request)
        var headers: [String: String] = [:]
        for field in request.headers {
            headers[String(field.name)] = String(field.value)
        }
        if let authResp = checkAuth(headers: headers, cors: cors) { return authResp }

        let mcpRequest = MCP.HTTPRequest(method: "DELETE", headers: headers, body: nil, path: "/mcp")
        let mcpResponse = await sessionManager.handleStatefulRequest(mcpRequest)

        return buildHummingbirdResponse(from: mcpResponse, cors: cors, toolName: "DELETE", elapsed: 0)
    }

    private func buildHummingbirdResponse(from mcpResponse: MCP.HTTPResponse, cors: HTTPFields, toolName: String, elapsed: Int) -> Response {
        Task { await recordRequest(tool: toolName, durationMs: elapsed, success: mcpResponse.statusCode >= 200 && mcpResponse.statusCode < 300) }

        let status: HTTPResponse.Status
        switch mcpResponse.statusCode {
        case 200: status = .ok
        case 202: status = .accepted
        case 400: status = .badRequest
        case 403: status = .forbidden
        case 404: status = .notFound
        case 405: status = .methodNotAllowed
        case 406: status = .notAcceptable
        case 409: status = .conflict
        case 429: status = .tooManyRequests
        default: status = .internalServerError
        }

        var responseHeaders: HTTPFields = [:]
        for (key, value) in mcpResponse.headers {
            if let name = HTTPField.Name(key) {
                responseHeaders[name] = value
            }
        }
        for field in cors {
            responseHeaders[field.name] = field.value
        }

        switch mcpResponse {
        case .stream(let stream, _):
            if responseHeaders[.contentType] == nil {
                responseHeaders[.contentType] = "text/event-stream"
            }
            let body = ResponseBody(asyncSequence: SSEAsyncSequence(stream: stream))
            return Response(status: status, headers: responseHeaders, body: body)

        default:
            if let data = mcpResponse.bodyData {
                if responseHeaders[.contentType] == nil {
                    responseHeaders[.contentType] = "application/json"
                }
                return Response(
                    status: status,
                    headers: responseHeaders,
                    body: .init(byteBuffer: .init(data: data))
                )
            }
            return Response(status: status, headers: responseHeaders)
        }
    }

    private func uiHTML() -> String {
        """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Vision OCR MCP - Dashboard</title>
            <script src="https://cdn.tailwindcss.com"></script>
            <script src="https://unpkg.com/alpinejs@3.x.x/dist/cdn.min.js" defer></script>
            <style>
                [x-cloak] { display: none !important; }
                .tab-active { border-bottom: 2px solid #3b82f6; color: #3b82f6; font-weight: 600; }
                .drop-active { border-color: #3b82f6 !important; background-color: #eff6ff !important; }
            </style>
        </head>
        <body class="bg-gray-50 min-h-screen" x-data="app()" x-init="init()">
            <header class="bg-white border-b border-gray-200 sticky top-0 z-10">
                <div class="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between">
                    <div class="flex items-center gap-3">
                        <h1 class="text-xl font-bold text-gray-900">Vision OCR MCP</h1>
                        <span class="text-xs px-2 py-0.5 bg-gray-100 text-gray-500 rounded-full" x-text="'v' + status.version"></span>
                    </div>
                    <div class="flex items-center gap-4">
                        <div class="flex items-center gap-1.5">
                            <span class="w-2 h-2 bg-green-500 rounded-full animate-pulse"></span>
                            <span class="text-sm text-green-600 font-medium" x-text="i18n[lang].running"></span>
                        </div>
                        <select x-model="lang" class="text-sm border rounded px-2 py-1 bg-white">
                            <option value="en">EN</option>
                            <option value="zh">中文</option>
                            <option value="ja">日本語</option>
                        </select>
                    </div>
                </div>
            </header>
            <div class="max-w-7xl mx-auto px-4">
                <nav class="flex gap-6 border-b border-gray-200 mt-4">
                    <button @click="tab='dashboard'" :class="tab==='dashboard' && 'tab-active'" class="pb-2 text-sm text-gray-600 hover:text-gray-900 transition" x-text="i18n[lang].tabDashboard"></button>
                    <button @click="tab='ocr'" :class="tab==='ocr' && 'tab-active'" class="pb-2 text-sm text-gray-600 hover:text-gray-900 transition" x-text="i18n[lang].tabOCR"></button>
                    <button @click="tab='history'" :class="tab==='history' && 'tab-active'" class="pb-2 text-sm text-gray-600 hover:text-gray-900 transition" x-text="i18n[lang].tabHistory"></button>
                    <button @click="tab='tools'" :class="tab==='tools' && 'tab-active'" class="pb-2 text-sm text-gray-600 hover:text-gray-900 transition" x-text="i18n[lang].tabTools"></button>
                    <button @click="tab='config'" :class="tab==='config' && 'tab-active'" class="pb-2 text-sm text-gray-600 hover:text-gray-900 transition" x-text="i18n[lang].tabConfig"></button>
                </nav>
            </div>
            <main class="max-w-7xl mx-auto px-4 py-6">
                <div x-show="tab==='dashboard'" x-cloak>
                    <div class="grid grid-cols-1 md:grid-cols-4 gap-4 mb-6">
                        <div class="bg-white rounded-lg shadow-sm border p-5"><p class="text-xs text-gray-500 uppercase tracking-wide" x-text="i18n[lang].uptime"></p><p class="text-2xl font-bold text-gray-900 mt-1" x-text="status.uptime || '--:--:--'"></p></div>
                        <div class="bg-white rounded-lg shadow-sm border p-5"><p class="text-xs text-gray-500 uppercase tracking-wide" x-text="i18n[lang].totalRequests"></p><p class="text-2xl font-bold text-gray-900 mt-1" x-text="metrics.totalRequests || 0"></p></div>
                        <div class="bg-white rounded-lg shadow-sm border p-5"><p class="text-xs text-gray-500 uppercase tracking-wide" x-text="i18n[lang].avgLatency"></p><p class="text-2xl font-bold text-gray-900 mt-1" x-text="(metrics.avgDurationMs || 0) + 'ms'"></p></div>
                        <div class="bg-white rounded-lg shadow-sm border p-5"><p class="text-xs text-gray-500 uppercase tracking-wide" x-text="i18n[lang].memory"></p><p class="text-2xl font-bold text-gray-900 mt-1" x-text="(status.memoryMB || 0) + ' MB'"></p></div>
                    </div>
                </div>
                <div x-show="tab==='ocr'" x-cloak>
                    <div class="grid grid-cols-1 lg:grid-cols-2 gap-6">
                        <div class="bg-white rounded-lg shadow-sm border p-6">
                            <h3 class="font-semibold text-gray-900 mb-4" x-text="i18n[lang].ocrTest"></h3>
                            <div class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center cursor-pointer transition" :class="isDragging && 'drop-active'" @dragover.prevent="isDragging=true" @dragleave="isDragging=false" @drop.prevent="isDragging=false; handleDrop($event)" @click="$refs.fileInput.click()">
                                <template x-if="!previewUrl">
                                    <div><svg class="mx-auto h-12 w-12 text-gray-400" stroke="currentColor" fill="none" viewBox="0 0 48 48"><path d="M28 8H12a4 4 0 00-4 4v20m32-12v8m0 0v8a4 4 0 01-4 4H12a4 4 0 01-4-4v-4m32-4l-3.172-3.172a4 4 0 00-5.656 0L28 28M8 32l9.172-9.172a4 4 0 015.656 0L28 28m0 0l4 4m4-24h8m-4-4v8m-12 4h.02" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg><p class="mt-2 text-sm text-gray-600" x-text="i18n[lang].dropHere"></p><p class="mt-1 text-xs text-gray-400">PNG, JPEG, HEIC, WebP, PDF</p></div>
                                </template>
                                <template x-if="previewUrl && !previewUrl.startsWith('pdf:')">
                                    <img :src="previewUrl" class="max-h-64 mx-auto rounded" alt="preview">
                                </template>
                                <template x-if="previewUrl && previewUrl.startsWith('pdf:')">
                                    <div class="flex flex-col items-center gap-2"><svg class="h-16 w-16 text-red-500" fill="currentColor" viewBox="0 0 24 24"><path d="M14 2H6a2 2 0 00-2 2v16a2 2 0 002 2h12a2 2 0 002-2V8l-6-6zM6 20V4h7v5h5v11H6z"/></svg><p class="text-sm text-gray-600 font-mono" x-text="previewUrl.substring(4)"></p></div>
                                </template>
                                <input type="file" x-ref="fileInput" @change="handleFile($event)" accept="image/*,.pdf" class="hidden">
                            </div>
                            <div class="mt-4 flex gap-3">
                                <select x-model="ocrFormat" class="text-sm border rounded px-3 py-1.5 bg-white"><option value="text">Text</option><option value="json">JSON</option><option value="markdown">Markdown</option></select>
                                <button @click="runOCR()" :disabled="!selectedFile || ocrLoading" class="px-4 py-1.5 bg-blue-600 text-white text-sm rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition"><span x-show="!ocrLoading" x-text="i18n[lang].recognize"></span><span x-show="ocrLoading">Processing...</span></button>
                                <button x-show="previewUrl" @click="clearOCR()" class="px-4 py-1.5 border text-sm rounded hover:bg-gray-50 transition" x-text="i18n[lang].clear"></button>
                            </div>
                            <p x-show="ocrTime" class="mt-2 text-xs text-gray-400" x-text="i18n[lang].processedIn + ' ' + ocrTime + 'ms'"></p>
                        </div>
                        <div class="bg-white rounded-lg shadow-sm border p-6">
                            <h3 class="font-semibold text-gray-900 mb-4" x-text="i18n[lang].result"></h3>
                            <div class="min-h-[200px] max-h-[500px] overflow-auto">
                                <template x-if="!ocrResult && !ocrLoading"><p class="text-gray-400 text-sm italic" x-text="i18n[lang].noResult"></p></template>
                                <pre x-show="ocrResult" x-text="ocrResult" class="whitespace-pre-wrap text-sm text-gray-800 font-mono leading-relaxed"></pre>
                            </div>
                            <div x-show="ocrResult" class="mt-4 flex gap-2">
                                <button @click="navigator.clipboard.writeText(ocrResult)" class="text-xs px-3 py-1 border rounded hover:bg-gray-50" x-text="i18n[lang].copy"></button>
                                <button @click="downloadResult()" class="text-xs px-3 py-1 border rounded hover:bg-gray-50" x-text="i18n[lang].download"></button>
                            </div>
                        </div>
                    </div>
                </div>
                <div x-show="tab==='history'" x-cloak>
                    <div class="bg-white rounded-lg shadow-sm border">
                        <div class="p-4 border-b flex justify-between items-center"><h3 class="font-semibold text-gray-900" x-text="i18n[lang].requestHistory"></h3><button @click="loadHistory()" class="text-sm text-blue-600 hover:text-blue-800" x-text="i18n[lang].refresh"></button></div>
                        <div class="overflow-x-auto"><table class="w-full text-sm"><thead class="bg-gray-50"><tr><th class="px-4 py-2 text-left text-gray-500 font-medium">#</th><th class="px-4 py-2 text-left text-gray-500 font-medium">Tool</th><th class="px-4 py-2 text-left text-gray-500 font-medium" x-text="i18n[lang].time"></th><th class="px-4 py-2 text-left text-gray-500 font-medium" x-text="i18n[lang].duration"></th><th class="px-4 py-2 text-left text-gray-500 font-medium" x-text="i18n[lang].status"></th></tr></thead><tbody><template x-for="item in history" :key="item.id"><tr class="border-t hover:bg-gray-50"><td class="px-4 py-2 text-gray-400" x-text="item.id"></td><td class="px-4 py-2 font-mono text-gray-800" x-text="item.tool"></td><td class="px-4 py-2 text-gray-500" x-text="new Date(item.timestamp).toLocaleTimeString()"></td><td class="px-4 py-2 text-gray-500" x-text="item.durationMs + 'ms'"></td><td class="px-4 py-2"><span :class="item.success ? 'text-green-600 bg-green-50' : 'text-red-600 bg-red-50'" class="px-2 py-0.5 rounded-full text-xs font-medium" x-text="item.success ? 'OK' : 'Error'"></span></td></tr></template><template x-if="history.length === 0"><tr><td colspan="5" class="px-4 py-8 text-center text-gray-400" x-text="i18n[lang].noHistory"></td></tr></template></tbody></table></div>
                    </div>
                </div>
                <div x-show="tab==='tools'" x-cloak>
                    <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
                        <template x-for="tool in tools" :key="tool.name"><div class="bg-white rounded-lg shadow-sm border p-5 hover:shadow-md transition"><div class="flex items-start justify-between"><h4 class="font-mono font-semibold text-gray-900" x-text="tool.name"></h4><span class="text-xs px-2 py-0.5 bg-blue-50 text-blue-600 rounded-full">MCP Tool</span></div><p class="text-sm text-gray-600 mt-2" x-text="tool.desc"></p><div class="mt-3 flex flex-wrap gap-1"><template x-for="param in tool.params" :key="param"><span class="text-xs px-2 py-0.5 bg-gray-100 text-gray-600 rounded font-mono" x-text="param"></span></template></div></div></template>
                    </div>
                </div>
                <div x-show="tab==='config'" x-cloak>
                    <div class="space-y-6 max-w-3xl">
                        <div class="bg-white rounded-lg shadow-sm border p-6"><h3 class="font-semibold text-gray-900 mb-4" x-text="i18n[lang].serverConfig"></h3><div class="space-y-3 text-sm"><template x-for="item in configItems" :key="item.key"><div class="flex items-center justify-between py-2 border-b border-gray-100"><div><p class="font-medium text-gray-800" x-text="item.key"></p></div><span class="font-mono text-gray-600 bg-gray-50 px-3 py-1 rounded" x-text="String(item.value)"></span></div></template></div></div>
                        <div class="bg-white rounded-lg shadow-sm border p-6"><h3 class="font-semibold text-gray-900 mb-3" x-text="i18n[lang].securitySettings"></h3><div class="space-y-3 text-sm"><div class="flex items-center justify-between py-2"><span class="text-gray-600" x-text="i18n[lang].apiKeyStatus"></span><span :class="config.hasApiKey ? 'text-green-600 bg-green-50' : 'text-amber-600 bg-amber-50'" class="px-2 py-0.5 rounded-full text-xs font-medium" x-text="config.hasApiKey ? 'Enabled (' + (config.apiKeySource||'') + ')' : 'Disabled'"></span></div></div><div class="mt-4 p-4 bg-blue-50 rounded-lg"><h4 class="text-sm font-semibold text-blue-800 mb-2" x-text="i18n[lang].howToSetKey"></h4><div class="space-y-2 text-xs text-blue-700 font-mono"><p># CLI flag:</p><p class="pl-2">vision-ocr-mcp serve --transport http --api-key "your-secret"</p><p class="mt-2"># Environment variable:</p><p class="pl-2">export VISION_OCR_MCP_API_KEY="your-secret"</p></div></div></div>
                    </div>
                </div>
            </main>
            <script>
            function app() {
                return {
                    tab: 'dashboard', lang: navigator.language.startsWith('zh') ? 'zh' : navigator.language.startsWith('ja') ? 'ja' : 'en',
                    status: {}, metrics: {}, config: {}, history: [],
                    tools: [
                        {name: 'ocr_extract_text', desc: 'Extract text from images/PDFs via file path, base64, or URL', params: ['file_path','base64','url','languages','format','pages']},
                        {name: 'analyze_document', desc: 'Structured document analysis with bounding boxes', params: ['file_path']},
                        {name: 'detect_text_regions', desc: 'Detect text regions with coordinates', params: ['file_path']},
                        {name: 'detect_barcodes', desc: 'Detect QR codes and barcodes', params: ['file_path']},
                        {name: 'detect_document_bounds', desc: 'Detect document boundaries for auto-crop', params: ['file_path']},
                        {name: 'ocr_screen_region', desc: 'Capture screen region and OCR', params: ['x','y','width','height']},
                        {name: 'ocr_clipboard', desc: 'OCR image from system clipboard', params: []},
                        {name: 'watch_folder', desc: 'Watch folder for auto-OCR', params: ['folder_path','action']},
                        {name: 'batch_ocr', desc: 'Process multiple files in batch', params: ['file_paths']},
                    ],
                    isDragging: false, selectedFile: null, previewUrl: null,
                    apiToken: localStorage.getItem('visionOcrApiToken') || '',
                    ocrResult: '', ocrFormat: 'text', ocrLoading: false, ocrTime: null,
                    i18n: {
                        en: {running:'Running',tabDashboard:'Dashboard',tabOCR:'OCR Test',tabHistory:'History',tabTools:'Tools',tabConfig:'Config',uptime:'Uptime',totalRequests:'Total Requests',avgLatency:'Avg Latency',memory:'Memory',ocrTest:'OCR Test',dropHere:'Drop image here or click to upload',recognize:'Recognize',clear:'Clear',processedIn:'Processed in',result:'Result',noResult:'Upload an image to start',copy:'Copy',download:'Download',requestHistory:'Request History',refresh:'Refresh',time:'Time',duration:'Duration',status:'Status',noHistory:'No requests yet',serverConfig:'Server Configuration',apiKey:'API Key',securitySettings:'Security Settings',apiKeyStatus:'API Key Status',howToSetKey:'How to Set API Key',enterApiKey:'Enter API Key:'},
                        zh: {running:'运行中',tabDashboard:'仪表盘',tabOCR:'OCR 测试',tabHistory:'请求历史',tabTools:'工具列表',tabConfig:'配置',uptime:'运行时长',totalRequests:'总请求数',avgLatency:'平均延迟',memory:'内存占用',ocrTest:'OCR 测试',dropHere:'拖拽图片到此处或点击上传',recognize:'识别',clear:'清除',processedIn:'处理耗时',result:'识别结果',noResult:'上传图片开始识别',copy:'复制',download:'下载',requestHistory:'请求历史',refresh:'刷新',time:'时间',duration:'耗时',status:'状态',noHistory:'暂无请求记录',serverConfig:'服务器配置',apiKey:'API 密钥',securitySettings:'安全设置',apiKeyStatus:'API 密钥状态',howToSetKey:'如何设置 API 密钥',enterApiKey:'请输入 API 密钥:'},
                        ja: {running:'稼働中',tabDashboard:'ダッシュボード',tabOCR:'OCRテスト',tabHistory:'リクエスト履歴',tabTools:'ツール一覧',tabConfig:'設定',uptime:'稼働時間',totalRequests:'総リクエスト',avgLatency:'平均レイテンシ',memory:'メモリ',ocrTest:'OCRテスト',dropHere:'画像をドラッグ＆ドロップ',recognize:'認識',clear:'クリア',processedIn:'処理時間',result:'認識結果',noResult:'画像をアップロードして開始',copy:'コピー',download:'ダウンロード',requestHistory:'リクエスト履歴',refresh:'更新',time:'時刻',duration:'処理時間',status:'ステータス',noHistory:'リクエスト履歴なし',serverConfig:'サーバー設定',apiKey:'APIキー',securitySettings:'セキュリティ設定',apiKeyStatus:'APIキーの状態',howToSetKey:'APIキーの設定方法',enterApiKey:'APIキーを入力:'}
                    },
                    configItems: [],
                    async init() { await this.loadStatus(); await this.loadMetrics(); await this.loadConfig(); await this.loadHistory(); setInterval(() => { this.loadStatus(); this.loadMetrics(); }, 5000); },
                    async loadStatus() { try { this.status = await (await fetch('/api/status')).json(); } catch(e) {} },
                    async loadMetrics() { try { this.metrics = await (await fetch('/api/metrics')).json(); } catch(e) {} },
                    async loadConfig() { try { this.config = await (await fetch('/api/config')).json(); this.configItems = Object.entries(this.config).map(([k,v]) => ({key:k,value:v})); } catch(e) {} },
                    async loadHistory() { try { this.history = (await (await fetch('/api/history')).json()).reverse(); } catch(e) {} },
                    handleDrop(event) { const file = event.dataTransfer.files[0]; if (file) this.loadFile(file); },
                    handleFile(event) { const file = event.target.files[0]; if (file) this.loadFile(file); },
                    loadFile(file) { this.selectedFile = file; this.ocrResult = ''; this.ocrTime = null; if (file.type.startsWith('image/')) { this.previewUrl = URL.createObjectURL(file); } else { this.previewUrl = 'pdf:' + file.name; } },
                    clearOCR() { this.selectedFile = null; this.previewUrl = null; this.ocrResult = ''; this.ocrTime = null; },
                    async runOCR() {
                        if (!this.selectedFile || this.ocrLoading) return;
                        this.ocrLoading = true; this.ocrResult = '';
                        const start = Date.now();
                        try {
                            const reader = new FileReader();
                            const base64 = await new Promise((resolve) => { reader.onload = (e) => resolve(e.target.result.split(',')[1]); reader.readAsDataURL(this.selectedFile); });
                            const hdrs = {'Content-Type': 'application/json', 'Accept': 'application/json'};
                            if (this.apiToken) hdrs['Authorization'] = 'Bearer ' + this.apiToken;
                            const initResp = await fetch('/mcp', { method: 'POST', headers: hdrs, body: JSON.stringify({jsonrpc: '2.0', id: 0, method: 'initialize', params: {protocolVersion: '2024-11-05', capabilities: {}, clientInfo: {name: 'vision-ocr-webui', version: '1.0.0'}}}) });
                            if (initResp.status === 401) { this.apiToken = prompt(this.i18n[this.lang].enterApiKey); if (this.apiToken) { localStorage.setItem('visionOcrApiToken', this.apiToken); this.ocrLoading = false; return this.runOCR(); } }
                            const resp = await fetch('/mcp', { method: 'POST', headers: hdrs, body: JSON.stringify({jsonrpc: '2.0', id: Date.now(), method: 'tools/call', params: {name: 'ocr_extract_text', arguments: {base64, format: this.ocrFormat}}}) });
                            const data = await resp.json();
                            if (data.error) { this.ocrResult = 'Error: ' + data.error.message; }
                            else { this.ocrResult = data.result?.content?.[0]?.text || JSON.stringify(data, null, 2); }
                            this.ocrTime = Date.now() - start;
                        } catch(e) { this.ocrResult = 'Error: ' + e.message; }
                        this.ocrLoading = false; this.loadHistory();
                    },
                    downloadResult() { const ext = this.ocrFormat === 'json' ? 'json' : this.ocrFormat === 'markdown' ? 'md' : 'txt'; const blob = new Blob([this.ocrResult], {type: 'text/plain'}); const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = 'ocr-result.' + ext; a.click(); }
                };
            }
            </script>
        </body>
        </html>
        """
    }
}

struct SSEAsyncSequence: AsyncSequence, Sendable {
    typealias Element = ByteBuffer

    let stream: AsyncThrowingStream<Data, Swift.Error>

    struct AsyncIterator: AsyncIteratorProtocol {
        var iterator: AsyncThrowingStream<Data, Swift.Error>.AsyncIterator

        mutating func next() async throws -> ByteBuffer? {
            guard let data = try await iterator.next() else { return nil }
            var buffer = ByteBuffer()
            buffer.writeBytes(data)
            return buffer
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(iterator: stream.makeAsyncIterator())
    }
}
