import Foundation
import Vision
import CoreGraphics

struct DocumentBoundsDetector: Sendable {
    func detect(from cgImage: CGImage) async throws -> [DocumentBounds] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectDocumentSegmentationRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(reason: error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRectangleObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let results: [DocumentBounds] = observations.map { obs in
                    DocumentBounds(
                        topLeft: Point(x: obs.topLeft.x, y: obs.topLeft.y),
                        topRight: Point(x: obs.topRight.x, y: obs.topRight.y),
                        bottomRight: Point(x: obs.bottomRight.x, y: obs.bottomRight.y),
                        bottomLeft: Point(x: obs.bottomLeft.x, y: obs.bottomLeft.y),
                        confidence: obs.confidence
                    )
                }

                continuation.resume(returning: results)
            }

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: OCRError.recognitionFailed(reason: error.localizedDescription))
            }
        }
    }

    func detect(fromFile path: String) async throws -> [DocumentBounds] {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            throw OCRError.fileNotFound(path: path)
        }

        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRError.imageLoadFailed(path: path, reason: "Cannot create CGImage")
        }

        return try await detect(from: cgImage)
    }
}
