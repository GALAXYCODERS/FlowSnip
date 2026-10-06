import Cocoa
import ScreenCaptureKit

extension Notification.Name {
    static let flowSnipCaptureFailure = Notification.Name("FlowSnipCaptureFailure")
}

@MainActor
final class CaptureEngine {

    nonisolated init() {}

    enum CaptureError: LocalizedError, Equatable {
        case invalidRegion
        case displayUnavailable
        case screenRecordingPermissionRequired

        var errorDescription: String? {
            switch self {
            case .invalidRegion:
                return "The selection must be a valid region within one display."
            case .displayUnavailable:
                return "The selected display is no longer available."
            case .screenRecordingPermissionRequired:
                return "Screen Recording permission is required to capture the screen."
            }
        }
    }

    // MARK: - Public API

    /// Captures a screen region and copies it to the clipboard.
    /// - Parameters:
    ///   - rect: The selection rectangle in screen coordinates (bottom-left origin).
    ///   - screen: The screen the selection was made on.
    ///   - completion: Called with `true` on success.
    func capture(rect: CGRect, screen: NSScreen, completion: @escaping (Bool) -> Void) {
        Task {
            do {
                let image = try await captureImage(rect: rect, screen: screen)
                try Task.checkCancellation()
                completion(copyToClipboard(image))
            } catch {
                if !(error is CancellationError) {
                    print("FlowSnip: Capture failed: \(error.localizedDescription)")
                    NotificationCenter.default.post(name: .flowSnipCaptureFailure, object: nil)
                }
                completion(false)
            }
        }
    }

    func captureImage(rect: CGRect, screen: NSScreen) async throws -> CGImage {
        try Task.checkCancellation()

        guard CGPreflightScreenCaptureAccess() else {
            throw CaptureError.screenRecordingPermissionRequired
        }
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            throw CaptureError.displayUnavailable
        }

        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        try Task.checkCancellation()

        guard let display = content.displays.first(where: { $0.displayID == screenNumber.uint32Value }) else {
            throw CaptureError.displayUnavailable
        }

        let ownApplications = content.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        let configuration = try Self.configuration(
            for: rect,
            screenFrame: screen.frame,
            pixelScale: CGFloat(filter.pointPixelScale)
        )
        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
        try Task.checkCancellation()
        return image
    }

    @discardableResult
    func copyToClipboard(_ image: CGImage, pasteboard: NSPasteboard = .general) -> Bool {
        let clipboardImage = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        pasteboard.clearContents()
        let success = pasteboard.writeObjects([clipboardImage])

        if success {
            print("FlowSnip: Copied \(image.width)x\(image.height) image to clipboard.")
        } else {
            print("FlowSnip: Failed to write image to clipboard.")
        }
        return success
    }

    // MARK: - Coordinate Conversion

    static func configuration(for rect: CGRect, screenFrame: CGRect, pixelScale: CGFloat) throws -> SCStreamConfiguration {
        guard rect.origin.x.isFinite, rect.origin.y.isFinite,
              rect.size.width.isFinite, rect.size.height.isFinite,
              rect.size.width > 0, rect.size.height > 0,
              screenFrame.contains(rect),
              pixelScale.isFinite, pixelScale > 0 else {
            throw CaptureError.invalidRegion
        }

        let pixelWidth = (rect.width * pixelScale).rounded(.up)
        let pixelHeight = (rect.height * pixelScale).rounded(.up)
        guard pixelWidth.isFinite, pixelHeight.isFinite,
              pixelWidth < CGFloat(Int.max), pixelHeight < CGFloat(Int.max) else {
            throw CaptureError.invalidRegion
        }

        let configuration = SCStreamConfiguration()
        configuration.sourceRect = CGRect(
            x: rect.minX - screenFrame.minX,
            y: screenFrame.maxY - rect.maxY,
            width: rect.width,
            height: rect.height
        )
        configuration.width = Int(pixelWidth)
        configuration.height = Int(pixelHeight)
        configuration.showsCursor = false
        configuration.captureResolution = .best
        return configuration
    }
}
