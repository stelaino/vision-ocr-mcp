import Foundation

enum OCRError: Error, LocalizedError, Sendable {
    case fileNotFound(path: String)
    case unsupportedFormat(extension: String)
    case imageLoadFailed(path: String, reason: String)
    case pdfLoadFailed(path: String, reason: String)
    case pdfPageOutOfRange(page: Int, total: Int)
    case recognitionFailed(reason: String)
    case emptyResult
    case invalidBase64
    case urlDownloadFailed(url: String, reason: String)
    case clipboardEmpty
    case screenCapturePermissionDenied
    case screenCaptureFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .unsupportedFormat(let ext):
            return "Unsupported file format: .\(ext)"
        case .imageLoadFailed(let path, let reason):
            return "Failed to load image '\(path)': \(reason)"
        case .pdfLoadFailed(let path, let reason):
            return "Failed to load PDF '\(path)': \(reason)"
        case .pdfPageOutOfRange(let page, let total):
            return "Page \(page) out of range (total: \(total))"
        case .recognitionFailed(let reason):
            return "Text recognition failed: \(reason)"
        case .emptyResult:
            return "No text recognized in the image"
        case .invalidBase64:
            return "Invalid Base64 encoded image data"
        case .urlDownloadFailed(let url, let reason):
            return "Failed to download image from '\(url)': \(reason)"
        case .clipboardEmpty:
            return "No image found in clipboard"
        case .screenCapturePermissionDenied:
            return "Screen capture permission denied. Grant access in System Settings > Privacy > Screen Recording"
        case .screenCaptureFailed(let reason):
            return "Screen capture failed: \(reason)"
        }
    }
}

enum ServerError: Error, LocalizedError, Sendable {
    case transportInitFailed(reason: String)
    case portInUse(port: Int)
    case invalidConfiguration(reason: String)
    case authenticationFailed
    case rateLimitExceeded
    case originNotAllowed(origin: String)

    var errorDescription: String? {
        switch self {
        case .transportInitFailed(let reason):
            return "Transport initialization failed: \(reason)"
        case .portInUse(let port):
            return "Port \(port) is already in use"
        case .invalidConfiguration(let reason):
            return "Invalid configuration: \(reason)"
        case .authenticationFailed:
            return "Authentication failed: invalid or missing API key"
        case .rateLimitExceeded:
            return "Rate limit exceeded"
        case .originNotAllowed(let origin):
            return "Origin not allowed: \(origin)"
        }
    }
}

enum ServiceError: Error, LocalizedError, Sendable {
    case alreadyInstalled
    case notInstalled
    case installFailed(reason: String)
    case uninstallFailed(reason: String)
    case startFailed(reason: String)
    case stopFailed(reason: String)

    var errorDescription: String? {
        switch self {
        case .alreadyInstalled:
            return "Service is already installed"
        case .notInstalled:
            return "Service is not installed"
        case .installFailed(let reason):
            return "Failed to install service: \(reason)"
        case .uninstallFailed(let reason):
            return "Failed to uninstall service: \(reason)"
        case .startFailed(let reason):
            return "Failed to start service: \(reason)"
        case .stopFailed(let reason):
            return "Failed to stop service: \(reason)"
        }
    }
}
