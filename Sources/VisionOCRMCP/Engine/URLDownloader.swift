import Foundation
import CoreGraphics
import ImageIO

struct URLDownloader: Sendable {
    func downloadImage(from urlString: String) async throws -> (CGImage, Data) {
        guard let url = URL(string: urlString) else {
            throw OCRError.urlDownloadFailed(url: urlString, reason: "Invalid URL")
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw OCRError.urlDownloadFailed(
                url: urlString,
                reason: "HTTP \(httpResponse.statusCode)"
            )
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRError.urlDownloadFailed(url: urlString, reason: "Cannot decode image data")
        }

        return (cgImage, data)
    }
}
