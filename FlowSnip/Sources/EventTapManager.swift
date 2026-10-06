import Cocoa
import Carbon

final class EventTapManager {
    private var hotKeys: [CaptureMode: EventHotKeyRef] = [:]
    private var eventHandler: EventHandlerRef?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var accessibilityRetryTimer: Timer?
    private var deduplicator = ShortcutDeduplicator()
    private var pressedCarbonActions: Set<CaptureMode> = []
    private(set) var aiShortcut = ShortcutChord.aiScan
    private(set) var registrationErrors: [CaptureMode: OSStatus] = [:]
    var onShortcutTriggered: (() -> Void)?
    var onActionTriggered: ((CaptureMode) -> Void)?
    var onRegistrationError: ((String) -> Void)?
    var isRunning: Bool { !hotKeys.isEmpty || globalMonitor != nil }
    private static var current: EventTapManager?

    func start() {
        stop()
        EventTapManager.current = self
        installCarbonHandler()
        register(.screenshot, chord: .screenshot)
        register(.aiScan, chord: aiShortcut)
        installGlobalMonitor()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.action(for: event) else { return event }
            self.dispatch(action, isRepeat: event.isARepeat)
            return nil
        }
        if globalMonitor == nil {
            startAccessibilityRetry()
        }
    }

    func stop() {
        for reference in hotKeys.values { UnregisterEventHotKey(reference) }
        hotKeys.removeAll()
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        accessibilityRetryTimer?.invalidate()
        accessibilityRetryTimer = nil
        registrationErrors.removeAll()
        deduplicator = ShortcutDeduplicator()
        pressedCarbonActions.removeAll()
        if EventTapManager.current === self { EventTapManager.current = nil }
    }

    deinit { stop() }

    @discardableResult
    func updateAIShortcut(_ chord: ShortcutChord) -> Bool {
        guard chord.isValid, chord != .screenshot else {
            onRegistrationError?("Choose a shortcut with Command or Control that differs from the screenshot shortcut.")
            return false
        }
        guard chord != aiShortcut else { return true }
        let previous = aiShortcut
        if let reference = hotKeys.removeValue(forKey: .aiScan) { UnregisterEventHotKey(reference) }
        aiShortcut = chord
        guard EventTapManager.current === self else { return true }
        if register(.aiScan, chord: chord) { return true }
        aiShortcut = previous
        register(.aiScan, chord: previous)
        return false
    }

    private func installCarbonHandler() {
        var eventTypes = [
            EventTypeSpec(eventClass: UInt32(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: UInt32(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))
        ]
        let handlerStatus = eventTypes.withUnsafeMutableBufferPointer { buffer in InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, _ in
                guard let event else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let result = GetEventParameter(event, UInt32(kEventParamDirectObject), UInt32(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard result == noErr, identifier.signature == OSType(0x464C_5350),
                      let action = CaptureMode.allCases.first(where: { $0.hotKeyID == identifier.id }) else {
                    return OSStatus(eventNotHandledErr)
                }
                guard let manager = EventTapManager.current else { return noErr }
                if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                    manager.pressedCarbonActions.remove(action)
                } else if manager.pressedCarbonActions.insert(action).inserted {
                    manager.dispatch(action)
                }
                return noErr
            },
            buffer.count, buffer.baseAddress, nil, &eventHandler
        ) }
        if handlerStatus != noErr {
            onRegistrationError?("Keyboard handler could not be installed (\(handlerStatus)).")
        }
    }

    @discardableResult
    private func register(_ action: CaptureMode, chord: ShortcutChord) -> Bool {
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(chord.keyCode, chord.modifiers, EventHotKeyID(signature: OSType(0x464C_5350), id: action.hotKeyID), GetApplicationEventTarget(), 0, &reference)
        if result == noErr, let reference {
            hotKeys[action] = reference
            registrationErrors.removeValue(forKey: action)
            return true
        } else {
            registrationErrors[action] = result
            onRegistrationError?("\(chord.label) could not be registered. It may be in use by another app (\(result)).")
            return false
        }
    }

    private func action(for event: NSEvent) -> CaptureMode? {
        let chord = ShortcutChord(event: event)
        if chord == .screenshot { return .screenshot }
        if chord == aiShortcut { return .aiScan }
        return nil
    }

    private func dispatch(_ action: CaptureMode, isRepeat: Bool = false) {
        guard deduplicator.accepts(action, at: ProcessInfo.processInfo.systemUptime, isRepeat: isRepeat) else { return }
        if let onActionTriggered {
            onActionTriggered(action)
        } else if action == .screenshot {
            onShortcutTriggered?()
        }
    }

    private func installGlobalMonitor() {
        guard globalMonitor == nil, AXIsProcessTrusted() else { return }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.action(for: event) else { return }
            self.dispatch(action, isRepeat: event.isARepeat)
        }
    }

    private func startAccessibilityRetry() {
        accessibilityRetryTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self = self else { timer.invalidate(); return }
            if AXIsProcessTrusted() {
                self.installGlobalMonitor()
                if self.globalMonitor != nil {
                    timer.invalidate()
                    self.accessibilityRetryTimer = nil
                }
            }
        }
    }
}
