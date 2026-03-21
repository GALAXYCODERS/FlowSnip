import Cocoa
import SwiftUI

/// Manages the full-screen overlay windows that appear on all connected displays
/// when a capture is triggered. Each screen gets its own borderless NSWindow with
/// a frosted glass backdrop and the interactive LiquidOverlayView.
final class OverlayWindowManager {

    // MARK: - Types

    typealias SelectionHandler = (CGRect, NSScreen) -> Void

    // MARK: - Properties

    private var overlayWindows: [NSWindow] = []
    private var selectionHandler: SelectionHandler?
    private var escapeMonitor: Any?

    /// Called when the overlay is dismissed (via Escape or after capture).
    var onDismiss: (() -> Void)?

    // MARK: - Public API

    /// Shows the capture overlay on all screens.
    /// - Parameter onSelection: Called with the selected rect (in screen coordinates) and the screen it belongs to.
    func showOverlay(onSelection: @escaping SelectionHandler) {
        // Clean up any existing overlay
        dismissOverlay(animated: false)

        self.selectionHandler = onSelection

        for screen in NSScreen.screens {
            let window = createOverlayWindow(for: screen)
            overlayWindows.append(window)
            window.orderFrontRegardless()
        }

        // Listen for Escape to cancel
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.dismissOverlay()
                return nil
            }
            return event
        }

        // Hide the cursor and show crosshair
        NSCursor.crosshair.push()
    }

    /// Dismisses all overlay windows with an optional fade animation.
    func dismissOverlay(animated: Bool = true) {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }

        NSCursor.pop()

        let windows = overlayWindows
        overlayWindows.removeAll()
        selectionHandler = nil

        let dismissCallback = onDismiss
        onDismiss = nil
        dismissCallback?()

        if animated {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                for window in windows {
                    window.animator().alphaValue = 0
                }
            }, completionHandler: {
                for window in windows {
                    window.orderOut(nil)
                }
            })
        } else {
            for window in windows {
                window.orderOut(nil)
            }
        }
    }

    // MARK: - Public API (Hide for Capture)

    /// Fully removes overlay windows from screen so CGWindowListCreateImage
    /// sees only the real desktop content. orderOut removes the windows from
    /// the window server's compositing list entirely.
    func hideOverlay() {
        // Remove the escape monitor so it doesn't interfere
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
        NSCursor.pop()

        for window in overlayWindows {
            window.orderOut(nil)
        }
        // Force the window server to process the removal immediately
        CATransaction.flush()
    }

    // MARK: - Window Creation

    private func createOverlayWindow(for screen: NSScreen) -> NSWindow {
        let window = NSWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )

        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        // Create the SwiftUI overlay content — no NSVisualEffectView backdrop
        // so the actual screen content remains visible through the transparent window.
        let overlayView = LiquidOverlayView(
            screenFrame: screen.frame,
            onSelectionComplete: { [weak self] rect in
                self?.handleSelection(rect: rect, screen: screen)
            },
            onCancel: { [weak self] in
                self?.dismissOverlay()
            }
        )

        let hostingView = NSHostingView(rootView: overlayView)
        hostingView.frame = screen.frame
        hostingView.autoresizingMask = [.width, .height]

        window.contentView = hostingView

        // Fade in
        window.alphaValue = 0
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.15
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            window.animator().alphaValue = 1
        }

        return window
    }

    // MARK: - Clipboard Toast

    private var toastWindow: NSWindow?

    /// Shows a "Copied to Clipboard" liquid glass toast centered near the bottom of the given screen.
    func showClipboardToast(on screen: NSScreen) {
        // Remove any existing toast
        toastWindow?.orderOut(nil)

        let toastSize = NSSize(width: 260, height: 52)
        let origin = NSPoint(
            x: screen.frame.midX - toastSize.width / 2,
            y: screen.frame.minY + screen.frame.height * 0.3 - toastSize.height / 2
        )

        let window = NSWindow(
            contentRect: NSRect(origin: origin, size: toastSize),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false,
            screen: screen
        )
        window.level = .floating
        window.isOpaque = false
        window.backgroundColor = .clear
        window.ignoresMouseEvents = true
        window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .transient]

        let hostingView = NSHostingView(rootView: ClipboardToastView())
        hostingView.frame = NSRect(origin: .zero, size: toastSize)
        window.contentView = hostingView
        window.orderFrontRegardless()

        self.toastWindow = window

        // Auto-dismiss after animations complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) { [weak self] in
            self?.toastWindow?.orderOut(nil)
            self?.toastWindow = nil
        }
    }

    // MARK: - Selection Handling

    private func handleSelection(rect: CGRect, screen: NSScreen) {
        guard rect.width > 5 && rect.height > 5 else {
            // Selection too small — ignore accidentally tiny drags
            return
        }
        selectionHandler?(rect, screen)
    }
}
