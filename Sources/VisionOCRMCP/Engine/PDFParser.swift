import Foundation
import PDFKit
import CoreGraphics

struct PDFParser: Sendable {
    let dpi: CGFloat

    init(dpi: CGFloat = 300) {
        self.dpi = dpi
    }

    func renderPages(from url: URL, range: ClosedRange<Int>?) throws -> [CGImage] {
        guard let document = PDFDocument(url: url) else {
            throw OCRError.pdfLoadFailed(path: url.path, reason: "Cannot open PDF document")
        }

        let totalPages = document.pageCount
        let pageRange: ClosedRange<Int>
        if let range {
            guard range.lowerBound >= 1, range.upperBound <= totalPages else {
                throw OCRError.pdfPageOutOfRange(page: range.upperBound, total: totalPages)
            }
            pageRange = range
        } else {
            pageRange = 1...totalPages
        }

        var images: [CGImage] = []
        for pageNum in pageRange {
            guard let page = document.page(at: pageNum - 1) else { continue }
            if let image = renderPage(page) {
                images.append(image)
            }
        }

        return images
    }

    func pageCount(at url: URL) throws -> Int {
        guard let document = PDFDocument(url: url) else {
            throw OCRError.pdfLoadFailed(path: url.path, reason: "Cannot open PDF document")
        }
        return document.pageCount
    }

    private func renderPage(_ page: PDFPage) -> CGImage? {
        let pageRect = page.bounds(for: .mediaBox)
        let scale = dpi / 72.0
        let width = Int(pageRect.width * scale)
        let height = Int(pageRect.height * scale)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)

        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }
}
