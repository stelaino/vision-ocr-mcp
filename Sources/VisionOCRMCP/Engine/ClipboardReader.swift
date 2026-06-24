import Foundation
import AppKit
import CoreGraphics

struct ClipboardReader: Sendable {
    func readImage() throws -> CGImage {
        let pasteboard = NSPasteboard.general

        guard let types = pasteboard.types else {
            throw OCRError.clipboardEmpty
        }

        if types.contains(.tiff),
           let data = pasteboard.data(forType: .tiff),
           let imageRep = NSBitmapImageRep(data: data),
           let cgImage = imageRep.cgImage {
            return cgImage
        }

        if types.contains(.png),
           let data = pasteboard.data(forType: .png),
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
            return cgImage
        }

        let imageTypes: [NSPasteboard.PasteboardType] = [
            .init("public.jpeg"),
            .init("public.heic"),
            .init("public.webp"),
        ]
        for type in imageTypes {
            if types.contains(type),
               let data = pasteboard.data(forType: type),
               let source = CGImageSourceCreateWithData(data as CFData, nil),
               let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) {
                return cgImage
            }
        }

        throw OCRError.clipboardEmpty
    }
}
