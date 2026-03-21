import Cocoa
import Carbon

/// Registers the global ⌘+Shift+2 shortcut using two parallel mechanisms:
///
/// 1. **Carbon Hot Key API** — no permissions needed, works on most macOS versions.
/// 2. **NSEvent global monitor** — requires Accessibility permission, more reliable on modern macOS.
///
/// Whichever fires first triggers the action; the other is harmlessly ignored.
final class EventTapManager {

    // MARK: - State

    private var hotKeyRef: EventHotKeyRef?
    private var globalMonitor: Any?
    private var accessibilityRetryTimer: Timer?

    /// Callback fired when ⌘+Shift+2 is detected.
    var onShortcutTriggered: (() -> Void)?

    /// Whether at least one mechanism is active.
    var isRunning: Bool { hotKeyRef != nil || globalMonitor != nil }

    // MARK: - Static reference for Carbon C callback

    private static var current: EventTapManager?

    // MARK: - Public API

    func start() {
        EventTapManager.current = self

        // Mechanism 1: Carbon Hot Key (no permissions needed)
        registerCarbonHotKey()

        // Mechanism 2: NSEvent global monitor (needs Accessibility)
        installGlobalMonitor()

        // If global monitor failed (no accessibility), retry periodically
        if globalMonitor == nil {
            startAccessibilityRetry()
        }
    }

    func stop() {
        unregisterCarbonHotKey()
        removeGlobalMonitor()
        accessibilityRetryTimer?.invalidate()
        accessibilityRetryTimer = nil
        if EventTapManager.current === self {
            EventTapManager.current = nil
        }
    }

    deinit {
        stop()
    }

    // MARK: - Mechanism 1: Carbon Hot Key

    private func registerCarbonHotKey() {
        guard hotKeyRef == nil else { return }

        var eventType = EventTypeSpec(
            eventClass: UInt32(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let handlerStatus = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_: EventHandlerCallRef?, _: EventRef?, _: UnsafeMutableRawPointer?) -> OSStatus in
                print("🔑 FlowSnip: Carbon hot key fired!")
                EventTapManager.current?.onShortcutTriggered?()
                return noErr
            },
            1,
            &eventType,
            nil,
            nil
        )

        guard handlerStatus == noErr else {
            print("❌ FlowSnip: InstallEventHandler failed (\(handlerStatus))")
            return
        }

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x464C_5350),  // "FLSP"
            id: UInt32(1)
        )

        let registerStatus = RegisterEventHotKey(
            UInt32(kVK_ANSI_2),              // 19 = physical "2" key (all layouts)
            UInt32(cmdKey | shiftKey),         // ⌘+Shift
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if registerStatus == noErr {
            print("✅ FlowSnip: Carbon hot key ⌘+Shift+2 registered")
        } else {
            print("❌ FlowSnip: RegisterEventHotKey failed (\(registerStatus))")
            hotKeyRef = nil
        }
    }

    private func unregisterCarbonHotKey() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }

    // MARK: - Mechanism 2: NSEvent Global Monitor

    private func installGlobalMonitor() {
        guard globalMonitor == nil else { return }

        // This silently fails without Accessibility permission — no crash, no error
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            // Check for ⌘+Shift+2
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            let isCmd = flags.contains(.command)
            let isShift = flags.contains(.shift)
            // Ensure ONLY ⌘+Shift are pressed (not also Control, Option, etc.)
            let noExtraModifiers = !flags.contains(.control) && !flags.contains(.option)

            if event.keyCode == 19 && isCmd && isShift && noExtraModifiers {
                print("🔑 FlowSnip: NSEvent global monitor fired!")
                self?.onShortcutTriggered?()
            }
        }

        if globalMonitor != nil {
            print("✅ FlowSnip: NSEvent global monitor installed (Accessibility granted)")
        } else {
            print("⚠️ FlowSnip: NSEvent global monitor not available (Accessibility not granted)")
        }
    }

    private func removeGlobalMonitor() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
    }

    // MARK: - Accessibility Retry

    /// Periodically checks if Accessibility was granted, then installs the global monitor.
    private func startAccessibilityRetry() {
        accessibilityRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }

            if AXIsProcessTrusted() {
                self.installGlobalMonitor()
                if self.globalMonitor != nil {
                    timer.invalidate()
                    self.accessibilityRetryTimer = nil
                    print("✅ FlowSnip: Accessibility granted — global monitor now active")
                }
            }
        }
    }
}
