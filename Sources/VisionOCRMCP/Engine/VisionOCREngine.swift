import Foundation
import Vision
import CoreImage

final class VisionOCREngine: Sendable {
    let config: OCRConfig

    init(config: OCRConfig = OCRConfig()) {
        self.config = config
    }

    func recognize(filePath: String, languages: [String]? = nil, pages: ClosedRange<Int>?) async throws -> OCRResult {
        let url = URL(fileURLWithPath: filePath)
        let ext = url.pathExtension.lowercased()

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw OCRError.fileNotFound(path: filePath)
        }

        let startTime = DispatchTime.now()

        let result: OCRResult
        if ext == "pdf" {
            result = try await recognizePDF(url: url, pages: pages)
        } else {
            guard Self.supportedImageExtensions.contains(ext) else {
                throw OCRError.unsupportedFormat(extension: ext)
            }
            result = try await recognizeImage(url: url)
        }

        let elapsed = DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds
        let ms = Int(elapsed / 1_000_000)

        return OCRResult(
            text: result.text,
            pages: result.pages,
            metadata: OCRMetadata(
                totalPages: result.pages.count,
                languages: config.languages,
                processingTimeMs: ms,
                imageSize: result.metadata.imageSize,
                format: ext
            )
        )
    }

    func recognizeFromBase64(_ base64String: String, pages pageRange: ClosedRange<Int>? = nil) async throws -> OCRResult {
        guard let data = Data(base64Encoded: base64String) else {
            throw OCRError.invalidBase64
        }

        if data.count >= 5, data.prefix(5) == Data([0x25, 0x50, 0x44, 0x46, 0x2D]) {
            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".pdf")
            try data.write(to: tempURL)
            defer { try? FileManager.default.removeItem(at: tempURL) }
            return try await recognizePDF(url: tempURL, pages: pageRange)
        }

        guard let cgImage = createCGImage(from: data) else {
            throw OCRError.imageLoadFailed(path: "<base64>", reason: "Cannot decode image data")
        }

        let startTime = DispatchTime.now()
        let pages = try await performOCR(on: cgImage, pageIndex: 1)
        let elapsed = Int((DispatchTime.now().uptimeNanoseconds - startTime.uptimeNanoseconds) / 1_000_000)

        let text = pages.flatMap(\.blocks).map(\.text).joined(separator: "\n")
        return OCRResult(
            text: text,
            pages: pages,
            metadata: OCRMetadata(
                totalPages: 1,
                languages: config.languages,
                processingTimeMs: elapsed,
                imageSize: ImageSize(width: cgImage.width, height: cgImage.height),
                format: "base64"
            )
        )
    }

    private func recognizeImage(url: URL) async throws -> OCRResult {
        guard let imageSource = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            throw OCRError.imageLoadFailed(path: url.path, reason: "Cannot create CGImage")
        }

        let pages = try await performOCR(on: cgImage, pageIndex: 1)
        let text = pages.flatMap(\.blocks).map(\.text).joined(separator: "\n")

        return OCRResult(
            text: text,
            pages: pages,
            metadata: OCRMetadata(
                totalPages: 1,
                languages: config.languages,
                processingTimeMs: 0,
                imageSize: ImageSize(width: cgImage.width, height: cgImage.height),
                format: url.pathExtension
            )
        )
    }

    private func recognizePDF(url: URL, pages: ClosedRange<Int>?) async throws -> OCRResult {
        let pdfParser = PDFParser()
        let images = try pdfParser.renderPages(from: url, range: pages)

        var allPages: [PageResult] = []
        for (index, cgImage) in images.enumerated() {
            let pageNum = (pages?.lowerBound ?? 1) + index
            let pageResults = try await performOCR(on: cgImage, pageIndex: pageNum)
            allPages.append(contentsOf: pageResults)
        }

        let text = allPages.flatMap(\.blocks).map(\.text).joined(separator: "\n")
        return OCRResult(
            text: text,
            pages: allPages,
            metadata: OCRMetadata(
                totalPages: allPages.count,
                languages: config.languages,
                processingTimeMs: 0,
                imageSize: nil,
                format: "pdf"
            )
        )
    }

    func performOCRPublic(on image: CGImage, pageIndex: Int) async throws -> [PageResult] {
        try await performOCR(on: image, pageIndex: pageIndex)
    }

    private func performOCR(on image: CGImage, pageIndex: Int) async throws -> [PageResult] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(reason: error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [PageResult(page: pageIndex, blocks: [])])
                    return
                }

                let blocks: [TextBlock] = observations.compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let box = observation.boundingBox
                    return TextBlock(
                        text: candidate.string,
                        confidence: candidate.confidence,
                        boundingBox: BoundingBox(
                            x: box.origin.x,
                            y: box.origin.y,
                            width: box.size.width,
                            height: box.size.height
                        ),
                        language: nil
                    )
                }

                continuation.resume(returning: [PageResult(page: pageIndex, blocks: blocks)])
            }

            request.recognitionLevel = config.recognitionLevel == .accurate ? .accurate : .fast
            request.recognitionLanguages = config.languages
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: image, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(reason: error.localizedDescription))
            }
        }
    }

    private func createCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    static let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "webp", "bmp", "gif"
    ]
}
