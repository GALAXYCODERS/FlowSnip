import Cocoa
import ScreenCaptureKit

extension Notification.Name {
    static let flowSnipCaptureFailure = Notification.Name("FlowSnipCaptureFailure")
}

/// Handles the actual screen capture and clipboard write pipeline.
/// Converts screen coordinates, captures the region via CGWindowListCreateImage
/// and writes to NSPasteboard.
final class CaptureEngine {

    // MARK: - Public API

    /// Captures a screen region and copies it to the clipboard.
    /// - Parameters:
    ///   - rect: The selection rectangle in screen coordinates (bottom-left origin).
    ///   - screen: The screen the selection was made on.
    ///   - completion: Called with `true` on success.
    func capture(rect: CGRect, screen: NSScreen, completion: @escaping (Bool) -> Void) {
        // Convert to the global display coordinate space for CGWindowListCreateImage
        let captureRect = convertToDisplayCoordinates(rect: rect, screen: screen)

        // Use CGWindowListCreateImage for simplicity and reliability
        // This captures everything visible on screen within the given rect
        guard let cgImage = CGWindowListCreateImage(
            captureRect,
            .optionOnScreenOnly,
            kCGNullWindowID,
            [.boundsIgnoreFraming, .bestResolution]
        ) else {
            print("❌ FlowSnip: Failed to capture screen region. Screen Recording permission may be missing.")
            NotificationCenter.default.post(name: .flowSnipCaptureFailure, object: nil)
            completion(false)
            return
        }

        // Convert CGImage → NSImage
        let nsImage = NSImage(cgImage: cgImage, size: NSSize(
            width: cgImage.width,
            height: cgImage.height
        ))

        // Write to clipboard
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let success = pasteboard.writeObjects([nsImage])

        if success {
            print("✅ FlowSnip: Captured \(cgImage.width)×\(cgImage.height) region to clipboard.")
        } else {
            print("❌ FlowSnip: Failed to write image to clipboard.")
        }

        completion(success)
    }

    // MARK: - Coordinate Conversion

    /// Converts an AppKit screen-coordinate rect to the global display coordinate
    /// system used by CGWindowListCreateImage.
    ///
    /// AppKit screen coordinates: origin at bottom-left of the primary display.
    /// CGWindowList/CoreGraphics: origin at top-left of the primary display.
    /// Note: CGWindowListCreateImage takes points (not pixels) — the .bestResolution
    /// flag handles Retina scaling automatically.
    private func convertToDisplayCoordinates(rect: CGRect, screen: NSScreen) -> CGRect {
        // Get the primary screen height for the Y-flip
        guard let primaryScreen = NSScreen.screens.first else {
            return rect
        }

        let primaryHeight = primaryScreen.frame.height

        // Flip the Y coordinate from bottom-left to top-left origin
        let flippedY = primaryHeight - rect.origin.y - rect.height

        // CGWindowListCreateImage works in display points, not pixels
        return CGRect(
            x: rect.origin.x,
            y: flippedY,
            width: rect.width,
            height: rect.height
        )
    }
}
