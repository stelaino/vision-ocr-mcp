import Foundation

struct ServerConfig: Sendable, Codable {
    var transport: TransportType = .stdio
    var host: String = "127.0.0.1"
    var port: Int = 8765
    var apiKey: String?
    var allowedOrigins: [String] = []
    var rateLimitPerMinute: Int = 120
    var enableUI: Bool = false
    var logLevel: String = "info"

    enum TransportType: String, Sendable, Codable {
        case stdio
        case http
    }

    var resolvedApiKey: String? {
        apiKey ?? ProcessInfo.processInfo.environment["VISION_OCR_MCP_API_KEY"]
    }
}

struct OCRConfig: Sendable, Codable {
    var recognitionLevel: RecognitionLevel = .accurate
    var languages: [String] = ["zh-Hans", "en"]
    var outputFormat: OutputFormat = .text
    var includeConfidence: Bool = true
    var includeBoundingBoxes: Bool = true
    var readingOrder: Bool = true

    enum RecognitionLevel: String, Sendable, Codable {
        case accurate
        case fast
    }

    enum OutputFormat: String, Sendable, Codable, CaseIterable {
        case text
        case json
        case markdown
    }
}

struct AppConfig: Sendable, Codable {
    var server: ServerConfig = ServerConfig()
    var ocr: OCRConfig = OCRConfig()

    static func load(from path: String? = nil) -> AppConfig {
        let configPath = path ?? defaultConfigPath
        guard let data = FileManager.default.contents(atPath: configPath) else {
            return AppConfig()
        }
        return (try? JSONDecoder().decode(AppConfig.self, from: data)) ?? AppConfig()
    }

    func save(to path: String? = nil) throws {
        let configPath = path ?? Self.defaultConfigPath
        let dir = (configPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: URL(fileURLWithPath: configPath))
    }

    static var defaultConfigPath: String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/vision-ocr-mcp/config.json"
    }
}
