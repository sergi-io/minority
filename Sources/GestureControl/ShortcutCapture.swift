import AppKit
import SwiftUI

extension ShortcutBinding {
    static func captured(from event: NSEvent) -> ShortcutBinding {
        // Arrow keys also carry numeric-pad/function flags. Only save modifiers
        // the user explicitly combines with the physical key.
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        let modifiers = [flags.contains(.control) ? "⌃" : "",
                         flags.contains(.option) ? "⌥" : "",
                         flags.contains(.shift) ? "⇧" : "",
                         flags.contains(.command) ? "⌘" : ""].joined()
        let specialKeys: [UInt16: String] = [
            123: "←", 124: "→", 125: "↓", 126: "↑",
            36: "↩", 76: "⌤", 48: "⇥", 49: "Space", 51: "⌫", 117: "⌦",
            53: "Esc", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17",
            79: "F18", 80: "F19", 90: "F20"
        ]
        let characters = event.charactersIgnoringModifiers?.uppercased() ?? ""
        let key = specialKeys[event.keyCode] ?? (characters.isEmpty ? "Key \(event.keyCode)" : characters)
        return ShortcutBinding(keyCode: event.keyCode, modifiers: UInt64(flags.rawValue), title: modifiers + key)
    }
}

@MainActor
final class ShortcutCapture: ObservableObject {
    @Published var value: ShortcutBinding? {
        didSet {
            if !publishingManualChange {
                composer.load(value, catalog: catalog)
                query = ""
            }
        }
    }
    @Published var composer = ShortcutComposer()
    @Published var query = ""
    let catalog = ShortcutKey.catalog()
    private var publishingManualChange = false

    func addManualKey(_ key: ShortcutKey) {
        composer.add(key)
        query = ""
        publishManualChange()
    }

    func removeManualKey(_ key: ShortcutKey) {
        composer.keys.removeAll { $0.id == key.id }
        publishManualChange()
    }

    private func publishManualChange() {
        publishingManualChange = true
        value = composer.binding
        publishingManualChange = false
    }

    /// Saving also commits a complete key name typed without pressing Enter.
    func prepareForSave() -> String? {
        guard !isCapturing else { return "Finish or cancel keyboard recording before saving." }
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty {
            let matches = composer.suggestions(for: text, catalog: catalog)
            let exact = matches.filter { key in
                ([key.name, key.label] + key.aliases).contains { $0.lowercased() == text.lowercased() }
            }
            guard let key = exact.count == 1 ? exact.first : (matches.count == 1 ? matches.first : nil) else {
                return "Choose a suggestion for ‘\(text)’ before saving."
            }
            addManualKey(key)
        }
        guard value != nil else { return "Complete the shortcut with one key and up to three modifiers." }
        return nil
    }

    @Published var isCapturing = false
    private var monitor: Any?
    private var inactiveObserver: NSObjectProtocol?

    func start() {
        cancel()
        isCapturing = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.consume(event) == true ? nil : event
        }
        inactiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.cancel() }
        }
    }

    @discardableResult
    func consume(_ event: NSEvent) -> Bool {
        guard isCapturing, event.type == .keyDown else { return false }
        if event.keyCode != 53 { value = .captured(from: event) }
        cancel()
        return true
    }

    func cancel() {
        if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
        if let inactiveObserver {
            NotificationCenter.default.removeObserver(inactiveObserver)
            self.inactiveObserver = nil
        }
        isCapturing = false
    }

    deinit {
        if let monitor { NSEvent.removeMonitor(monitor) }
        if let inactiveObserver { NotificationCenter.default.removeObserver(inactiveObserver) }
    }
}

struct ShortcutCaptureField: NSViewRepresentable {
    let capture: ShortcutCapture

    func makeNSView(context: Context) -> ShortcutKeyView {
        let view = ShortcutKeyView()
        view.capture = capture
        return view
    }

    func updateNSView(_ view: ShortcutKeyView, context: Context) {
        view.capture = capture
    }
}

final class ShortcutKeyView: NSTextField {
    weak var capture: ShortcutCapture?

    init() {
        super.init(frame: .zero)
        stringValue = "Press your shortcut now…"
        isEditable = false
        isSelectable = false
        alignment = .center
        focusRingType = .exterior
        setAccessibilityLabel("Keyboard shortcut recorder")
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(self)
    }

    // Command combinations may be routed as key equivalents instead of text
    // input. Consume both routes before a menu or text editor handles them.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if capture?.consume(event) == true { return true }
        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if capture?.consume(event) != true { super.keyDown(with: event) }
    }
}
