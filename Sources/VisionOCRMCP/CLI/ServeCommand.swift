import ArgumentParser
import Logging

struct ServeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "serve",
        abstract: "Start the MCP server"
    )

    @Option(name: .shortAndLong, help: "Transport type: stdio or http")
    var transport: String = "stdio"

    @Option(name: .shortAndLong, help: "Port for HTTP transport")
    var port: Int = 8765

    @Option(name: .long, help: "Host to bind for HTTP transport")
    var host: String = "127.0.0.1"

    @Option(name: .long, help: "API key for HTTP authentication")
    var apiKey: String?

    @Flag(name: .long, help: "Enable Web UI dashboard")
    var ui: Bool = false

    @Option(name: .long, help: "Allowed origins (comma-separated)")
    var allowedOrigins: String?

    @Option(name: .long, help: "Rate limit per minute")
    var rateLimit: Int = 120

    @Option(name: .long, help: "Log level: trace, debug, info, warning, error")
    var logLevel: String = "info"

    func run() async throws {
        let logger = Logger(label: "com.stelaino.vision-ocr-mcp")

        let config = ServerConfig(
            transport: transport == "http" ? .http : .stdio,
            host: host,
            port: port,
            apiKey: apiKey,
            allowedOrigins: allowedOrigins?.split(separator: ",").map(String.init) ?? [],
            rateLimitPerMinute: rateLimit,
            enableUI: ui,
            logLevel: logLevel
        )

        switch config.transport {
        case .stdio:
            logger.info("Starting MCP server with stdio transport")
            let server = MCPServerSetup(config: config, logger: logger)
            try await server.startStdio()

        case .http:
            logger.info("Starting MCP server with HTTP transport on \(config.host):\(config.port)")
            if config.enableUI {
                logger.info("Web UI available at http://\(config.host):\(config.port)/ui")
            }
            let server = MCPServerSetup(config: config, logger: logger)
            try await server.startHTTP()
        }
    }
}
