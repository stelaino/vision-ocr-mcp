import Foundation
import CoreGraphics
import ImageIO

struct ImageParser: Sendable {
    func loadImage(from path: String) throws -> CGImage {
        let url = URL(fileURLWithPath: path)
        return try loadImage(from: url)
    }

    func loadImage(from url: URL) throws -> CGImage {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw OCRError.imageLoadFailed(path: url.path, reason: "Cannot create image source")
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRError.imageLoadFailed(path: url.path, reason: "Cannot create image from source")
        }

        return image
    }

    func loadImage(from data: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw OCRError.invalidBase64
        }

        guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw OCRError.imageLoadFailed(path: "<data>", reason: "Cannot create image from data")
        }

        return image
    }

    func imageSize(at path: String) throws -> ImageSize {
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            throw OCRError.imageLoadFailed(path: path, reason: "Cannot create image source")
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else {
            throw OCRError.imageLoadFailed(path: path, reason: "Cannot read image dimensions")
        }

        return ImageSize(width: width, height: height)
    }

    static func isSupported(extension ext: String) -> Bool {
        VisionOCREngine.supportedImageExtensions.contains(ext.lowercased())
    }
}
