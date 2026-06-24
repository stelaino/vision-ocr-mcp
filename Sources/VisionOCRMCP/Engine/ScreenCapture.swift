import Foundation
import CoreGraphics

struct ScreenCapture: Sendable {
    func capture(region: CGRect?) throws -> CGImage {
        let rect = region ?? CGRect.infinite

        guard let image = CGWindowListCreateImage(
            rect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.bestResolution, .boundsIgnoreFraming]
        ) else {
            if CGPreflightScreenCaptureAccess() == false {
                throw OCRError.screenCapturePermissionDenied
            }
            throw OCRError.screenCaptureFailed(reason: "Failed to capture screen region")
        }

        return image
    }
}
