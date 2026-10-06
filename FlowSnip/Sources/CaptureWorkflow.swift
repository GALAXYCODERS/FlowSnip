import Cocoa
import Carbon

enum CaptureMode: String, CaseIterable, Codable, Sendable {
    case screenshot
    case aiScan

    var hotKeyID: UInt32 { self == .screenshot ? 1 : 2 }
}

struct ShortcutChord: Codable, Equatable, Sendable {
    var keyCode: UInt32
    var modifiers: UInt32

    static let screenshot = ShortcutChord(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey))
    static let aiScan = ShortcutChord(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | shiftKey | optionKey))

    var isValid: Bool {
        let allowedModifiers = UInt32(cmdKey | shiftKey | optionKey | controlKey)
        return keyCode <= 126 && keyCode != UInt32(kVK_Escape)
            && modifiers & UInt32(cmdKey | controlKey) != 0
            && modifiers & ~allowedModifiers == 0
    }

    var label: String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("Control") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("Option") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("Shift") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("Command") }
        let names: [UInt32: String] = [0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M", 49: "Space", 123: "Left", 124: "Right", 125: "Down", 126: "Up"]
        parts.append(names[keyCode] ?? "Key \(keyCode)")
        return parts.joined(separator: " + ")
    }

    init(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = UInt32(event.keyCode)
        let flags = event.modifierFlags
        modifiers = 0
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
    }
}

struct ShortcutDeduplicator {
    private var lastAction: CaptureMode?
    private var lastTime = -Double.infinity

    mutating func accepts(_ action: CaptureMode, at time: TimeInterval, isRepeat: Bool = false) -> Bool {
        guard !isRepeat, time.isFinite else { return false }
        guard action != lastAction || time - lastTime >= 0.25 else { return false }
        lastAction = action
        lastTime = time
        return true
    }
}

enum ScanPhase: String, Sendable {
    case idle, selecting, capturing, preparing, analyzing, ready, failed
}

struct ScanSessionGate {
    private(set) var sessionID: UUID?
    private(set) var phase: ScanPhase = .idle

    mutating func begin() -> UUID {
        let identifier = UUID()
        sessionID = identifier
        phase = .selecting
        return identifier
    }

    @discardableResult
    mutating func advance(_ identifier: UUID, to nextPhase: ScanPhase) -> Bool {
        guard sessionID == identifier, phase != .idle, nextPhase != .idle else { return false }
        phase = nextPhase
        return true
    }

    func contains(_ identifier: UUID) -> Bool { sessionID == identifier }

    mutating func cancel() {
        sessionID = nil
        phase = .idle
    }
}

enum AssistantPanelPlacement {
    static func frame(near selection: CGRect, visibleFrame: CGRect) -> CGRect {
        let horizontalInset = min(16, max(0, visibleFrame.width / 4))
        let verticalInset = min(16, max(0, visibleFrame.height / 4))
        let width = min(460, max(1, visibleFrame.width - horizontalInset * 2))
        let height = min(560, max(1, visibleFrame.height - verticalInset * 2))
        let preferredX = selection.maxX + width + 16 <= visibleFrame.maxX ? selection.maxX + 12 : selection.minX - width - 12
        return CGRect(x: min(max(preferredX, visibleFrame.minX + horizontalInset), visibleFrame.maxX - width - horizontalInset),
            y: min(max(selection.midY - height / 2, visibleFrame.minY + verticalInset), visibleFrame.maxY - height - verticalInset),
            width: width, height: height)
    }
}

struct ReasoningStreamFilter {
    private var buffer = ""
    private var thinking: Bool
    init(thinking: Bool = false) { self.thinking = thinking }

    mutating func consume(_ chunk: String) -> String {
        buffer += chunk
        var output = ""
        while !buffer.isEmpty {
            let marker = thinking ? "</think>" : "<think>"
            if let range = buffer.range(of: marker) {
                if !thinking { output += buffer[..<range.lowerBound] }
                buffer = String(buffer[range.upperBound...])
                thinking.toggle()
            } else {
                let retained = (1..<marker.count).reversed().first { buffer.hasSuffix(String(marker.prefix($0))) } ?? 0
                if !thinking { output += buffer.dropLast(retained) }
                buffer = retained == 0 ? "" : String(buffer.suffix(retained))
                break
            }
        }
        return output
    }

    mutating func finish() -> String {
        defer { buffer = "" }
        return thinking ? "" : buffer
    }
}