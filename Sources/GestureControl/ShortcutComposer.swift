import AppKit
import Carbon

struct ShortcutKey: Identifiable, Equatable {
    let id: String
    let name: String
    let label: String
    let aliases: [String]
    let keyCode: UInt16?
    let modifier: NSEvent.ModifierFlags

    static let modifiers: [ShortcutKey] = [
        .init(id: "control", name: "Control", label: "⌃", aliases: ["ctrl"], keyCode: nil, modifier: .control),
        .init(id: "option", name: "Option", label: "⌥", aliases: ["alt", "alternate"], keyCode: nil, modifier: .option),
        .init(id: "shift", name: "Shift", label: "⇧", aliases: [], keyCode: nil, modifier: .shift),
        .init(id: "command", name: "Command", label: "⌘", aliases: ["cmd", "super"], keyCode: nil, modifier: .command)
    ]

    static func key(_ code: UInt16, _ name: String, label: String? = nil, aliases: [String] = []) -> ShortcutKey {
        .init(id: "key-\(code)", name: name, label: label ?? name, aliases: aliases, keyCode: code, modifier: [])
    }

    static func catalog() -> [ShortcutKey] {
        let special: [ShortcutKey] = [
            key(123, "Left Arrow", label: "←", aliases: ["left"]),
            key(124, "Right Arrow", label: "→", aliases: ["right"]),
            key(125, "Down Arrow", label: "↓", aliases: ["down"]),
            key(126, "Up Arrow", label: "↑", aliases: ["up"]),
            key(36, "Return", label: "↩", aliases: ["enter"]), key(76, "Keypad Enter", label: "⌤"),
            key(48, "Tab", label: "⇥"), key(49, "Space", aliases: ["spacebar"]),
            key(51, "Backspace", label: "⌫", aliases: ["delete"]), key(117, "Forward Delete", label: "⌦", aliases: ["del"]),
            key(53, "Escape", label: "Esc", aliases: ["esc"]), key(115, "Home"), key(119, "End"),
            key(116, "Page Up", aliases: ["pgup"]), key(121, "Page Down", aliases: ["pgdn"])
        ]
        let functionCodes: [UInt16] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113, 106, 64, 79, 80, 90]
        let functions = functionCodes.enumerated().map { key($0.element, "F\($0.offset + 1)") }
        let physicalKeys: [(UInt16, String)] = [
            (0,"A"),(1,"S"),(2,"D"),(3,"F"),(4,"H"),(5,"G"),(6,"Z"),(7,"X"),(8,"C"),(9,"V"),
            (10,"§"),(11,"B"),(12,"Q"),(13,"W"),(14,"E"),(15,"R"),(16,"Y"),(17,"T"),
            (18,"1"),(19,"2"),(20,"3"),(21,"4"),(22,"6"),(23,"5"),(24,"="),(25,"9"),(26,"7"),
            (27,"-"),(28,"8"),(29,"0"),(30,"]"),(31,"O"),(32,"U"),(33,"["),(34,"I"),(35,"P"),
            (37,"L"),(38,"J"),(39,"'"),(40,"K"),(41,";"),(42,"\\"),(43,","),(44,"/"),(45,"N"),(46,"M"),(47,"."),(50,"`")
        ]
        let input = TISCopyCurrentASCIICapableKeyboardLayoutInputSource().takeRetainedValue()
        let layoutData = TISGetInputSourceProperty(input, kTISPropertyUnicodeKeyLayoutData)
        let printable = physicalKeys.map { code, fallback -> ShortcutKey in
            var title = fallback
            if let layoutData {
                let data = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue()
                let layout = UnsafeRawPointer(CFDataGetBytePtr(data)).assumingMemoryBound(to: UCKeyboardLayout.self)
                var deadKeyState: UInt32 = 0
                var length = 0
                var characters = [UniChar](repeating: 0, count: 8)
                let status = UCKeyTranslate(layout, code, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                            OptionBits(1 << kUCKeyTranslateNoDeadKeysBit), &deadKeyState,
                                            characters.count, &length, &characters)
                if status == noErr, length > 0 {
                    title = String(utf16CodeUnits: characters, count: length).uppercased()
                }
            }
            return key(code, title)
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return modifiers + special + printable + functions
    }
}

struct ShortcutComposer {
    static let maximumKeys = 4
    var keys: [ShortcutKey] = []

    var binding: ShortcutBinding? {
        guard keys.count <= Self.maximumKeys, let primary = keys.first(where: { $0.keyCode != nil }),
              keys.filter({ $0.keyCode != nil }).count == 1 else { return nil }
        let flags = keys.reduce(NSEvent.ModifierFlags()) { $0.union($1.modifier) }
        let prefix = ShortcutKey.modifiers.filter { flags.contains($0.modifier) }.map(\.label).joined()
        return ShortcutBinding(keyCode: primary.keyCode!, modifiers: UInt64(flags.rawValue), title: prefix + primary.label)
    }

    mutating func load(_ binding: ShortcutBinding?, catalog: [ShortcutKey]) {
        guard let binding else { keys = []; return }
        let flags = NSEvent.ModifierFlags(rawValue: UInt(binding.modifiers))
        keys = ShortcutKey.modifiers.filter { flags.contains($0.modifier) }
        keys.append(catalog.first { $0.keyCode == binding.keyCode }
                    ?? .key(binding.keyCode, "Key \(binding.keyCode)"))
    }

    func canAdd(_ key: ShortcutKey) -> Bool {
        guard keys.count < Self.maximumKeys, !keys.contains(where: { $0.id == key.id }) else { return false }
        if key.keyCode != nil { return !keys.contains { $0.keyCode != nil } }
        return keys.filter { $0.keyCode == nil }.count < Self.maximumKeys - 1
    }

    mutating func add(_ key: ShortcutKey) {
        if canAdd(key) { keys.append(key) }
    }

    func suggestions(for query: String, catalog: [ShortcutKey]) -> [ShortcutKey] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return catalog.filter { key in
            canAdd(key) && (text.isEmpty || ([key.name, key.label] + key.aliases).contains {
                $0.lowercased().contains(text)
            })
        }.sorted { a, b in
            func exact(_ key: ShortcutKey) -> Bool {
                ([key.name, key.label] + key.aliases).contains { $0.lowercased() == text }
            }
            return exact(a) && !exact(b)
        }
    }
}
