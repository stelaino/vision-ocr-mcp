import Foundation

struct OCRResult: Codable, Sendable {
    let text: String
    let pages: [PageResult]
    let metadata: OCRMetadata
}

struct PageResult: Codable, Sendable {
    let page: Int
    let blocks: [TextBlock]
}

struct TextBlock: Codable, Sendable {
    let text: String
    let confidence: Float
    let boundingBox: BoundingBox
    let language: String?
}

struct BoundingBox: Codable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
}

struct OCRMetadata: Codable, Sendable {
    let totalPages: Int
    let languages: [String]
    let processingTimeMs: Int
    let imageSize: ImageSize?
    let format: String
}

struct ImageSize: Codable, Sendable {
    let width: Int
    let height: Int
}

struct BarcodeResult: Codable, Sendable {
    let payload: String
    let symbology: String
    let boundingBox: BoundingBox
    let confidence: Float
}

struct DocumentBounds: Codable, Sendable {
    let topLeft: Point
    let topRight: Point
    let bottomRight: Point
    let bottomLeft: Point
    let confidence: Float
}

struct Point: Codable, Sendable {
    let x: Double
    let y: Double
}
