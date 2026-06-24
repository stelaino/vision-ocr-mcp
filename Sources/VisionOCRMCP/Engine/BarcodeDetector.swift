import Foundation
import Vision
import CoreGraphics

struct BarcodeDetector: Sendable {
    func detect(from cgImage: CGImage) async throws -> [BarcodeResult] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectBarcodesRequest { request, error in
                if let error {
                    continuation.resume(throwing: OCRError.recognitionFailed(reason: error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNBarcodeObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                let results: [BarcodeResult] = observations.compactMap { obs in
                    guard let payload = obs.payloadStringValue else { return nil }
                    let box = obs.boundingBox
                    return BarcodeResult(
                        payload: payload,
                        symbology: obs.symbology.rawValue,
                        boundingBox: BoundingBox(
                            x: box.origin.x,
                            y: box.origin.y,
                            width: box.size.width,
                            height: box.size.height
                        ),
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

    func detect(fromFile path: String) async throws -> [BarcodeResult] {
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
