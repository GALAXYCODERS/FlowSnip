import Cocoa
import Carbon.HIToolbox

/// Manages a global CGEventTap to detect the ⌘+Shift+2 keyboard shortcut.
/// Fires `onShortcutTriggered` instantly when the shortcut is pressed.
final class EventTapManager {

    // MARK: - State

    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isOverlayActive = false

    /// Callback fired on the main thread when ⌘+Shift+2 is detected.
    var onShortcutTriggered: (() -> Void)?

    /// Whether the event tap is currently installed and active.
    var isRunning: Bool { eventTap != nil }

    // MARK: - Public API

    /// Installs the global event tap. Requires Accessibility permission.
    func start() {
        // Don't install twice
        guard eventTap == nil else { return }

        let eventMask: CGEventMask = (1 << CGEventType.keyDown.rawValue)

        let userInfo = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: eventMask,
            callback: eventTapCallback,
            userInfo: userInfo
        ) else {
            print("❌ FlowSnip: Failed to create CGEventTap. Check Accessibility permission.")
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)

        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("✅ FlowSnip: Global event tap installed successfully.")
        }
    }

    /// Removes the global event tap.
    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    /// Set by OverlayWindowManager when overlay is shown/hidden.
    func setOverlayActive(_ active: Bool) {
        isOverlayActive = active
    }

    // MARK: - Event Handling

    fileprivate func handleEvent(_ type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        // ⌘ + Shift + 2 (instant trigger)
        if keyCode == 19 && type == .keyDown
            && flags.contains(.maskCommand) && flags.contains(.maskShift) {
            // Ignore auto-repeat
            if event.getIntegerValueField(.keyboardEventAutorepeat) != 0 {
                return nil
            }
            DispatchQueue.main.async {
                self.onShortcutTriggered?()
            }
            return nil // Swallow the event
        }

        return Unmanaged.passUnretained(event)
    }
}

// MARK: - C Callback

/// C-compatible callback for CGEvent.tapCreate. Forwards events to our manager.
private func eventTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    // Handle tap being disabled by the system (e.g., too slow)
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let userInfo = userInfo {
            let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
            if let tap = manager.eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
        }
        return Unmanaged.passUnretained(event)
    }

    guard let userInfo = userInfo else {
        return Unmanaged.passUnretained(event)
    }

    let manager = Unmanaged<EventTapManager>.fromOpaque(userInfo).takeUnretainedValue()
    return manager.handleEvent(type, event: event)
}
