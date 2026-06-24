import ArgumentParser

@main
struct VisionOCRMCP: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "vision-ocr-mcp",
        abstract: "macOS native offline OCR with MCP protocol support",
        version: "0.9.0",
        subcommands: [ServeCommand.self, OCRCommand.self, ServiceCommand.self],
        defaultSubcommand: ServeCommand.self
    )
}
