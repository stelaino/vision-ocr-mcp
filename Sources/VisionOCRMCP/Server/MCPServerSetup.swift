import Foundation
import Logging
import MCP

final class MCPServerSetup: Sendable {
    let config: ServerConfig
    let logger: Logger

    init(config: ServerConfig, logger: Logger) {
        self.config = config
        self.logger = logger
    }

    func startStdio() async throws {
        let server = Server(
            name: "vision-ocr-mcp",
            version: "0.9.0",
            capabilities: .init(tools: .init(listChanged: false))
        )

        let toolRegistry = ToolRegistry()
        await toolRegistry.registerTools(on: server)

        let transport = StdioTransport(logger: logger)

        logger.info("Starting MCP server (stdio transport)")
        try await server.start(transport: transport)
        await server.waitUntilCompleted()
    }

    func startHTTP() async throws {
        let validationPipeline = StandardValidationPipeline(validators: [
            OriginValidator.disabled,
            ContentTypeValidator(),
        ])

        let sessionManager = MCPSessionManager(
            config: config,
            validationPipeline: validationPipeline,
            logger: logger
        )

        let httpBridge = HTTPTransportBridge(
            config: config,
            sessionManager: sessionManager,
            logger: logger
        )
        try await httpBridge.start()
    }
}
