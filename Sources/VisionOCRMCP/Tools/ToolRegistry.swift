import Foundation
import MCP

final class ToolRegistry: @unchecked Sendable {
    let engine = VisionOCREngine()
    let barcodeDetector = BarcodeDetector()
    let documentBoundsDetector = DocumentBoundsDetector()
    let screenCapture = ScreenCapture()
    let clipboardReader = ClipboardReader()
    let urlDownloader = URLDownloader()
    let folderWatcher: FolderWatcher

    init() {
        folderWatcher = FolderWatcher(engine: engine)
    }

    func registerTools(on server: Server) async {
        await server.withMethodHandler(ListTools.self) { [self] _ in
            ListTools.Result(tools: self.toolDefinitions)
        }

        await server.withMethodHandler(CallTool.self) { [self] params in
            try await self.handleToolCall(params)
        }
    }

    private func handleToolCall(_ params: CallTool.Parameters) async throws -> CallTool.Result {
        let arguments = params.arguments ?? [:]
        do {
            let text = try await executeToolCall(name: params.name, arguments: arguments)
            return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
        } catch let error as OCRError {
            var msg = "Error: \(error.localizedDescription)"
            if case .fileNotFound(_) = error {
                msg += "\nHint: If the user uploaded/pasted an image, use the 'base64' parameter instead of 'file_path'. Only use file_path for files that actually exist on the server disk."
            }
            return CallTool.Result(
                content: [.text(text: msg, annotations: nil, _meta: nil)],
                isError: true
            )
        } catch {
            return CallTool.Result(
                content: [.text(text: "Error: \(error.localizedDescription)", annotations: nil, _meta: nil)],
                isError: true
            )
        }
    }

    private func executeToolCall(name: String, arguments: [String: Value]) async throws -> String {
        switch name {
        case "ocr_extract_text":
            return try await handleOCRExtract(arguments: arguments)
        case "analyze_document":
            return try await handleAnalyzeDocument(arguments: arguments)
        case "detect_text_regions":
            return try await handleDetectRegions(arguments: arguments)
        case "detect_barcodes":
            return try await handleDetectBarcodes(arguments: arguments)
        case "detect_document_bounds":
            return try await handleDetectDocumentBounds(arguments: arguments)
        case "ocr_screen_region":
            return try await handleScreenRegionOCR(arguments: arguments)
        case "ocr_clipboard":
            return try await handleClipboardOCR(arguments: arguments)
        case "watch_folder":
            return try await handleWatchFolder(arguments: arguments)
        case "batch_ocr":
            return try await handleBatchOCR(arguments: arguments)
        default:
            throw OCRError.recognitionFailed(reason: "Unknown tool: \(name)")
        }
    }

    // MARK: - ocr_extract_text

    private func resolveFilePath(_ rawPath: String) throws -> String {
        let expanded = (rawPath as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            return expanded
        }

        let resolved = (expanded as NSString).standardizingPath
        if FileManager.default.fileExists(atPath: resolved) {
            return resolved
        }

        if expanded.hasPrefix("file://") {
            let urlPath = URL(string: expanded)?.path ?? expanded
            if FileManager.default.fileExists(atPath: urlPath) {
                return urlPath
            }
        }

        let candidates = [
            FileManager.default.currentDirectoryPath + "/" + rawPath,
            FileManager.default.homeDirectoryForCurrentUser.path + "/" + rawPath,
            FileManager.default.homeDirectoryForCurrentUser.path + "/Desktop/" + rawPath,
            FileManager.default.homeDirectoryForCurrentUser.path + "/Downloads/" + rawPath,
            FileManager.default.homeDirectoryForCurrentUser.path + "/Documents/" + rawPath,
        ]
        for candidate in candidates {
            if FileManager.default.fileExists(atPath: candidate) {
                return candidate
            }
        }

        throw OCRError.fileNotFound(path: rawPath)
    }

    private func handleOCRExtract(arguments: [String: Value]) async throws -> String {
        let format = arguments["format"]?.stringValue ?? "text"
        let languages = arguments["languages"]?.stringValue
        let languageArray = languages?.split(separator: "+").map(String.init)

        let result: OCRResult

        if let filePath = arguments["file_path"]?.stringValue {
            let path = try resolveFilePath(filePath)
            result = try await engine.recognize(filePath: path, languages: languageArray, pages: parsePages(arguments["pages"]?.stringValue))
        } else if let base64 = arguments["base64"]?.stringValue {
            let cleanBase64 = base64.replacingOccurrences(
                of: "data:[^;]+;base64,", with: "", options: .regularExpression)
            result = try await engine.recognizeFromBase64(cleanBase64)
        } else if let urlString = arguments["url"]?.stringValue {
            let (cgImage, _) = try await urlDownloader.downloadImage(from: urlString)
            let pages = try await engine.performOCRPublic(on: cgImage, pageIndex: 1)
            let text = pages.flatMap(\.blocks).map(\.text).joined(separator: "\n")
            let ocrResult = OCRResult(
                text: text,
                pages: pages,
                metadata: OCRMetadata(
                    totalPages: 1,
                    languages: engine.config.languages,
                    processingTimeMs: 0,
                    imageSize: ImageSize(width: cgImage.width, height: cgImage.height),
                    format: "url"
                )
            )
            return try formatOutput(ocrResult, format: format)
        } else {
            throw OCRError.recognitionFailed(reason: "Must provide file_path, base64, or url")
        }

        if let outputPath = arguments["output_path"]?.stringValue {
            let path = (outputPath as NSString).expandingTildeInPath
            let content = try formatOutput(result, format: format)
            try content.write(toFile: path, atomically: true, encoding: .utf8)
        }

        return try formatOutput(result, format: format)
    }

    // MARK: - analyze_document

    private func handleAnalyzeDocument(arguments: [String: Value]) async throws -> String {
        guard let filePath = arguments["file_path"]?.stringValue else {
            throw OCRError.recognitionFailed(reason: "file_path is required")
        }
        let path = try resolveFilePath(filePath)
        let result = try await engine.recognize(filePath: path, languages: nil, pages: nil)
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(result)
        return String(data: data, encoding: .utf8) ?? result.text
    }

    // MARK: - detect_text_regions

    private func handleDetectRegions(arguments: [String: Value]) async throws -> String {
        guard let filePath = arguments["file_path"]?.stringValue else {
            throw OCRError.recognitionFailed(reason: "file_path is required")
        }
        let path = try resolveFilePath(filePath)
        let result = try await engine.recognize(filePath: path, languages: nil, pages: nil)
        let regions = result.pages.flatMap(\.blocks).map { block -> [String: Any] in
            ["text": block.text, "x": block.boundingBox.x, "y": block.boundingBox.y,
             "width": block.boundingBox.width, "height": block.boundingBox.height,
             "confidence": Double(block.confidence)]
        }
        let data = try JSONSerialization.data(withJSONObject: regions, options: .prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - detect_barcodes

    private func handleDetectBarcodes(arguments: [String: Value]) async throws -> String {
        guard let filePath = arguments["file_path"]?.stringValue else {
            throw OCRError.recognitionFailed(reason: "file_path is required")
        }
        let path = try resolveFilePath(filePath)
        let results = try await barcodeDetector.detect(fromFile: path)

        if results.isEmpty {
            return "No barcodes detected in the image."
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(results)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - detect_document_bounds

    private func handleDetectDocumentBounds(arguments: [String: Value]) async throws -> String {
        guard let filePath = arguments["file_path"]?.stringValue else {
            throw OCRError.recognitionFailed(reason: "file_path is required")
        }
        let path = try resolveFilePath(filePath)
        let results = try await documentBoundsDetector.detect(fromFile: path)

        if results.isEmpty {
            return "No document boundaries detected in the image."
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(results)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - ocr_screen_region

    private func handleScreenRegionOCR(arguments: [String: Value]) async throws -> String {
        let x = arguments["x"]?.numericDoubleValue ?? 0
        let y = arguments["y"]?.numericDoubleValue ?? 0
        let width = arguments["width"]?.numericDoubleValue ?? 0
        let height = arguments["height"]?.numericDoubleValue ?? 0

        let region: CGRect?
        if width > 0 && height > 0 {
            region = CGRect(x: x, y: y, width: width, height: height)
        } else {
            region = nil
        }

        let cgImage = try screenCapture.capture(region: region)
        let pages = try await engine.performOCRPublic(on: cgImage, pageIndex: 1)
        let text = pages.flatMap(\.blocks).map(\.text).joined(separator: "\n")

        if text.isEmpty {
            return "No text detected in the screen region."
        }
        return text
    }

    // MARK: - ocr_clipboard

    private func handleClipboardOCR(arguments: [String: Value]) async throws -> String {
        let cgImage = try clipboardReader.readImage()
        let pages = try await engine.performOCRPublic(on: cgImage, pageIndex: 1)
        let text = pages.flatMap(\.blocks).map(\.text).joined(separator: "\n")

        if text.isEmpty {
            return "No text detected in clipboard image."
        }
        return text
    }

    // MARK: - watch_folder

    private func handleWatchFolder(arguments: [String: Value]) async throws -> String {
        if let action = arguments["action"]?.stringValue, action == "stop" {
            if let folderPath = arguments["folder_path"]?.stringValue {
                await folderWatcher.stopWatching(folder: folderPath)
                return "Stopped watching: \(folderPath)"
            }
            return "folder_path is required for stop action"
        }

        if let action = arguments["action"]?.stringValue, action == "list" {
            let folders = await folderWatcher.getWatchedFolders()
            if folders.isEmpty {
                return "No folders being watched."
            }
            return "Watched folders:\n" + folders.joined(separator: "\n")
        }

        guard let folderPath = arguments["folder_path"]?.stringValue else {
            throw OCRError.recognitionFailed(reason: "folder_path is required")
        }
        return try await folderWatcher.watch(folder: folderPath)
    }

    // MARK: - batch_ocr

    private func handleBatchOCR(arguments: [String: Value]) async throws -> String {
        guard let filePathsValue = arguments["file_paths"],
              case .array(let valuesArray) = filePathsValue else {
            throw OCRError.recognitionFailed(reason: "file_paths array is required")
        }
        let filePaths = valuesArray.compactMap(\.stringValue)

        var results: [[String: Any]] = []
        for filePath in filePaths {
            let path: String
            do {
                path = try resolveFilePath(filePath)
            } catch {
                results.append(["file": filePath, "error": error.localizedDescription])
                continue
            }
            do {
                let result = try await engine.recognize(filePath: path, languages: nil, pages: nil)
                results.append(["file": filePath, "text": result.text])
            } catch {
                results.append(["file": filePath, "error": error.localizedDescription])
            }
        }
        let data = try JSONSerialization.data(withJSONObject: results, options: .prettyPrinted)
        return String(data: data, encoding: .utf8) ?? "[]"
    }

    // MARK: - Helpers

    private func parsePages(_ pagesString: String?) -> ClosedRange<Int>? {
        guard let pages = pagesString else { return nil }
        let parts = pages.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 2, parts[0] <= parts[1] else { return nil }
        return parts[0]...parts[1]
    }

    private func formatOutput(_ result: OCRResult, format: String) throws -> String {
        switch format {
        case "json":
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(result)
            return String(data: data, encoding: .utf8) ?? result.text
        case "markdown":
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
        default:
            return result.text
        }
    }

    // MARK: - Tool Definitions

    var toolDefinitions: [Tool] {
        [
            Tool(
                name: "ocr_extract_text",
                description: "Extract text from images (PNG/JPEG/HEIC/WebP/TIFF) or multi-page PDFs using macOS Vision Framework. Provide ONE of: base64 (PREFERRED for inline/uploaded images), file_path (only for files already on the server disk), or url (remote HTTP image). When a user pastes or uploads an image in chat, always use base64 — do NOT invent a file_path.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "base64": .object([
                            "type": .string("string"),
                            "description": .string("PREFERRED. Base64-encoded image/PDF data (with or without data URI prefix). Use this when the user uploads, pastes, or attaches an image in conversation.")
                        ]),
                        "file_path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path to a file already on the server disk. Only use when the user explicitly mentions a specific file path. Do NOT fabricate paths. Example: /Users/name/Desktop/scan.png")
                        ]),
                        "url": .object([
                            "type": .string("string"),
                            "description": .string("HTTP/HTTPS URL of a remote image to download and OCR. Use when user provides a web link.")
                        ]),
                        "languages": .object([
                            "type": .string("string"),
                            "description": .string("OCR languages joined by '+'. Supported: zh-Hans, zh-Hant, en, ja, ko, fr, de, es, pt, it, ru. Default: zh-Hans+en")
                        ]),
                        "format": .object([
                            "type": .string("string"),
                            "description": .string("Output format. 'text': plain text only. 'json': full structured result with pages, blocks, confidence, bounding boxes. 'markdown': formatted with headers and metadata."),
                            "enum": .array([.string("text"), .string("json"), .string("markdown")])
                        ]),
                        "pages": .object([
                            "type": .string("string"),
                            "description": .string("Page range for multi-page PDFs, e.g. '1-3' for pages 1 through 3. Omit to process all pages.")
                        ]),
                        "output_path": .object([
                            "type": .string("string"),
                            "description": .string("If provided, write OCR results to this file path instead of returning inline")
                        ])
                    ])
                ])
            ),
            Tool(
                name: "analyze_document",
                description: "Perform deep structural analysis on a document image or PDF. Returns full JSON with every text block's content, confidence score (0-1), and normalized bounding box (x, y, width, height in 0-1 range). Use this when you need positional layout information, not just text content.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "file_path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path to document image or PDF. Example: ~/Documents/invoice.pdf")
                        ]),
                        "include_boxes": .object([
                            "type": .string("boolean"),
                            "description": .string("Include normalized bounding box coordinates for each text block (default: true)")
                        ]),
                        "include_confidence": .object([
                            "type": .string("boolean"),
                            "description": .string("Include recognition confidence score 0-1 for each block (default: true)")
                        ])
                    ]),
                    "required": .array([.string("file_path")])
                ])
            ),
            Tool(
                name: "detect_text_regions",
                description: "Detect all text regions in an image and return their spatial coordinates. Returns a JSON array where each entry has: text content, bounding box (x, y, width, height normalized 0-1), and confidence. Useful for understanding text layout and spatial relationships between text elements.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "file_path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path to image file. Example: /tmp/screenshot.png")
                        ])
                    ]),
                    "required": .array([.string("file_path")])
                ])
            ),
            Tool(
                name: "detect_barcodes",
                description: "Scan an image for QR codes and barcodes. Supports: QR, Aztec, EAN-8, EAN-13, UPC-E, Code 39, Code 93, Code 128, ITF-14, PDF417, Data Matrix, and more. Returns JSON array with each detected code's payload string, symbology type, and bounding box.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "file_path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path to image containing barcodes or QR codes. Example: ~/Desktop/label.jpg")
                        ])
                    ]),
                    "required": .array([.string("file_path")])
                ])
            ),
            Tool(
                name: "detect_document_bounds",
                description: "Detect document edges in a photo (e.g. a receipt, card, or paper on a desk). Returns the four corner points (topLeft, topRight, bottomRight, bottomLeft) in normalized coordinates (0-1) and a confidence score. Useful for perspective correction and auto-cropping.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "file_path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path to photo of a document. Example: ~/Photos/receipt.heic")
                        ])
                    ]),
                    "required": .array([.string("file_path")])
                ])
            ),
            Tool(
                name: "ocr_screen_region",
                description: "Capture the current macOS screen (or a specific rectangular region) and perform OCR on it. Omit all parameters to capture the entire screen. Coordinates are in screen pixels from top-left origin. Requires Screen Recording permission in System Settings > Privacy & Security.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "x": .object([
                            "type": .string("number"),
                            "description": .string("X coordinate (pixels from left edge of screen)")
                        ]),
                        "y": .object([
                            "type": .string("number"),
                            "description": .string("Y coordinate (pixels from top edge of screen)")
                        ]),
                        "width": .object([
                            "type": .string("number"),
                            "description": .string("Width of capture region in pixels")
                        ]),
                        "height": .object([
                            "type": .string("number"),
                            "description": .string("Height of capture region in pixels")
                        ])
                    ])
                ])
            ),
            Tool(
                name: "ocr_clipboard",
                description: "Read the image currently in the macOS system clipboard (e.g. from Cmd+Shift+4 screenshot or copied image) and extract all text from it. No parameters needed. Returns error if clipboard contains no image data.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([:])
                ])
            ),
            Tool(
                name: "watch_folder",
                description: "Monitor a folder for newly added image/PDF files and automatically run OCR on them. Three actions: 'start' (default) begins watching a folder, 'stop' stops watching, 'list' shows all currently watched folders. OCR results are saved as .txt files alongside the originals.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "folder_path": .object([
                            "type": .string("string"),
                            "description": .string("Absolute path to folder. Required for 'start' and 'stop' actions. Example: ~/Desktop/scans")
                        ]),
                        "action": .object([
                            "type": .string("string"),
                            "description": .string("'start': begin watching (default). 'stop': stop watching a folder. 'list': show all watched folders."),
                            "enum": .array([.string("start"), .string("stop"), .string("list")])
                        ])
                    ])
                ])
            ),
            Tool(
                name: "batch_ocr",
                description: "Process multiple image/PDF files in a single request. Returns a JSON array with one entry per file: {file, text} on success or {file, error} on failure. More efficient than calling ocr_extract_text repeatedly.",
                inputSchema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "file_paths": .object([
                            "type": .string("array"),
                            "description": .string("Array of absolute file paths to process. Example: [\"/tmp/a.png\", \"/tmp/b.pdf\"]"),
                            "items": .object(["type": .string("string")])
                        ])
                    ]),
                    "required": .array([.string("file_paths")])
                ])
            ),
        ]
    }
}

extension Value {
    var numericDoubleValue: Double? {
        if let d = self.doubleValue { return d }
        if let i = self.intValue { return Double(i) }
        if let s = self.stringValue { return Double(s) }
        return nil
    }
}
