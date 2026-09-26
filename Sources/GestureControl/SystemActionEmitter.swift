import AppKit
import ApplicationServices

struct SystemActionEmitter {
    func emit(_ binding: GestureBinding, scrollAmount: Int) {
        guard Self.hasAccessibilityPermission else { return }
        switch binding {
        case .scrollDown: scroll(-scrollAmount)
        case .scrollUp: scroll(scrollAmount)
        case .browserBack: key(33, modifiers: .maskCommand)
        case .shortcut(let shortcut): key(shortcut.keyCode, modifiers: CGEventFlags(rawValue: shortcut.modifiers))
        case .text(let text):
            for event in Self.textEvents(for: text) { event.post(tap: .cghidEventTap) }
        }
    }

    /// Unicode payloads type text without replacing the user's clipboard.
    /// Keep each event small and never split a UTF-16 surrogate pair.
    static func textEvents(for text: String) -> [CGEvent] {
        var chunks: [[UInt16]] = []
        var current: [UInt16] = []
        for scalar in text.unicodeScalars {
            let units = Array(String(scalar).utf16)
            if current.count + units.count > 20 {
                chunks.append(current)
                current = []
            }
            current.append(contentsOf: units)
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks.flatMap { units -> [CGEvent] in
            guard let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false) else { return [] }
            for event in [down, up] {
                event.flags = []
                event.keyboardSetUnicodeString(stringLength: units.count, unicodeString: units)
            }
            return [down, up]
        }
    }

    private func scroll(_ amount: Int) {
        guard amount != 0 else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        guard let event = CGEvent(scrollWheelEvent2Source: source, units: .line, wheelCount: 1,
                                  wheel1: Int32(amount), wheel2: 0, wheel3: 0) else { return }
        event.post(tap: .cghidEventTap)
    }

    private func key(_ code: CGKeyCode, modifiers: CGEventFlags) {
        guard let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true),
              let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false) else { return }
        down.flags = modifiers
        up.flags = modifiers
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    static var hasAccessibilityPermission: Bool { AXIsProcessTrusted() }

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
