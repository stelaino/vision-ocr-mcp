import ArgumentParser
import Foundation

struct OCRCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ocr",
        abstract: "Extract text from images or PDFs"
    )

    @Argument(help: "Input file path or directory")
    var input: String

    @Option(name: .shortAndLong, help: "Output file path")
    var output: String?

    @Option(name: .long, help: "Output directory for batch mode")
    var outputDir: String?

    @Option(name: .shortAndLong, help: "Output format: text, json, markdown")
    var format: String = "text"

    @Option(name: .shortAndLong, help: "Recognition languages (e.g. zh-Hans+en)")
    var lang: String = "zh-Hans+en"

    @Option(name: .long, help: "Page range for PDFs (e.g. 1-5)")
    var pages: String?

    @Flag(name: .long, help: "Use fast recognition (less accurate)")
    var fast: Bool = false

    func run() async throws {
        let languages = lang.split(separator: "+").map(String.init)
        let outputFormat: OCRConfig.OutputFormat = switch format {
        case "json": .json
        case "markdown", "md": .markdown
        default: .text
        }

        let config = OCRConfig(
            recognitionLevel: fast ? .fast : .accurate,
            languages: languages,
            outputFormat: outputFormat
        )

        let engine = VisionOCREngine(config: config)
        let inputPath = (input as NSString).expandingTildeInPath

        let isDirectory = FileManager.default.isDirectory(atPath: inputPath)

        if isDirectory {
            try await processBatch(engine: engine, directory: inputPath, config: config)
        } else {
            let result = try await engine.recognize(filePath: inputPath, pages: parsePageRange())
            try outputResult(result, format: outputFormat)
        }
    }

    private func parsePageRange() -> ClosedRange<Int>? {
        guard let pages else { return nil }
        let parts = pages.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, parts[0] <= parts[1] else { return nil }
        return parts[0]...parts[1]
    }

    private func processBatch(engine: VisionOCREngine, directory: String, config: OCRConfig) async throws {
        let supportedExtensions = ["png", "jpg", "jpeg", "heic", "tiff", "tif", "webp", "bmp", "gif", "pdf"]
        let files = try FileManager.default.contentsOfDirectory(atPath: directory)
            .filter { file in
                let ext = (file as NSString).pathExtension.lowercased()
                return supportedExtensions.contains(ext)
            }
            .map { "\(directory)/\($0)" }

        for file in files {
            let result = try await engine.recognize(filePath: file, pages: nil)

            if let outputDir {
                let dirPath = (outputDir as NSString).expandingTildeInPath
                try FileManager.default.createDirectory(atPath: dirPath, withIntermediateDirectories: true)
                let fileName = (file as NSString).lastPathComponent
                let outputExt = config.outputFormat == .json ? "json" : config.outputFormat == .markdown ? "md" : "txt"
                let outputPath = "\(dirPath)/\(fileName).\(outputExt)"
                try writeResult(result, format: config.outputFormat, to: outputPath)
            } else {
                try outputResult(result, format: config.outputFormat)
            }
        }
    }

    private func outputResult(_ result: OCRResult, format: OCRConfig.OutputFormat) throws {
        let content = formatResult(result, format: format)

        if let output {
            let path = (output as NSString).expandingTildeInPath
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        } else {
            print(content)
        }
    }

    private func writeResult(_ result: OCRResult, format: OCRConfig.OutputFormat, to path: String) throws {
        let content = formatResult(result, format: format)
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func formatResult(_ result: OCRResult, format: OCRConfig.OutputFormat) -> String {
        switch format {
        case .text:
            return result.text
        case .json:
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            guard let data = try? encoder.encode(result),
                  let json = String(data: data, encoding: .utf8) else {
                return result.text
            }
            return json
        case .markdown:
            return formatAsMarkdown(result)
        }
    }

    private func formatAsMarkdown(_ result: OCRResult) -> String {
        var md = "# OCR Result\n\n"
        md += "**Languages:** \(result.metadata.languages.joined(separator: ", "))\n"
        md += "**Processing Time:** \(result.metadata.processingTimeMs)ms\n\n"

        for page in result.pages {
            if result.pages.count > 1 {
                md += "## Page \(page.page)\n\n"
            }
            for block in page.blocks {
                md += "\(block.text)\n\n"
            }
        }
        return md
    }
}

extension FileManager {
    func isDirectory(atPath path: String) -> Bool {
        var isDir: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }
}
