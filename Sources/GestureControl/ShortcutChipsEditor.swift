import SwiftUI

struct ShortcutChipsEditor: View {
    @ObservedObject var editor: ShortcutCapture
    @State private var highlighted = 0
    @FocusState private var focused: Bool

    private var suggestions: [ShortcutKey] { Array(editor.composer.suggestions(for: editor.query, catalog: editor.catalog).prefix(8)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Build shortcut").font(.caption.weight(.semibold))
                Spacer()
                Text("\(editor.composer.keys.count)/\(ShortcutComposer.maximumKeys) keys").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            HStack(spacing: 6) {
                ForEach(editor.composer.keys) { key in
                    HStack(spacing: 4) {
                        Text(key.label).font(.subheadline.monospaced())
                        Button {
                            editor.removeManualKey(key)
                            focused = true
                        } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(key.name)")
                    }
                    .padding(.horizontal, 9).padding(.vertical, 7)
                    .background(Color.indigo.opacity(0.12), in: Capsule())
                    .help(key.name)
                }
                if editor.composer.keys.count < ShortcutComposer.maximumKeys {
                    TextField("Type a key…", text: $editor.query)
                        .textFieldStyle(.plain)
                        .focused($focused)
                        .onSubmit { addHighlighted() }
                        .onMoveCommand { direction in
                            if direction == .down { highlighted = min(highlighted + 1, suggestions.count - 1) }
                            if direction == .up { highlighted = max(0, highlighted - 1) }
                        }
                        .onExitCommand { focused = false }
                        .accessibilityLabel("Search shortcut keys")
                } else {
                    Spacer(minLength: 0)
                }
            }
            .padding(8)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(focused ? Color.indigo : Color.secondary.opacity(0.25)))

            if focused && editor.composer.keys.count < ShortcutComposer.maximumKeys {
                VStack(alignment: .leading, spacing: 2) {
                    if suggestions.isEmpty {
                        Text("No matching key. Try Command, Alt, Right Arrow, A, or F1.")
                            .font(.caption).foregroundStyle(.secondary).padding(8)
                    }
                    ForEach(Array(suggestions.enumerated()), id: \.element.id) { index, key in
                        Button { add(key) } label: {
                            HStack {
                                Text(key.name)
                                Spacer()
                                Text(key.label).monospaced()
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(index == highlighted ? Color.indigo.opacity(0.12) : .clear,
                                        in: RoundedRectangle(cornerRadius: 6))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(4)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
            }
            Text(editor.composer.keys.count > ShortcutComposer.maximumKeys
                 ? "This recorded shortcut has more than \(ShortcutComposer.maximumKeys) keys. Remove keys to edit it manually."
                 : "Choose one key and up to three modifiers. Example: Command + Alt + Right Arrow. Enter adds a suggestion; × removes a key.")
                .font(.caption).foregroundStyle(.secondary)
            if !editor.composer.keys.isEmpty && editor.composer.binding == nil && editor.composer.keys.count <= ShortcutComposer.maximumKeys {
                Text("Add a key such as Right Arrow to complete the shortcut.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .onChange(of: editor.query) { _ in highlighted = 0 }
    }

    private func addHighlighted() {
        guard suggestions.indices.contains(highlighted) else { return }
        add(suggestions[highlighted])
    }

    private func add(_ key: ShortcutKey) {
        editor.addManualKey(key)
        highlighted = 0
        focused = editor.composer.keys.count < ShortcutComposer.maximumKeys
    }
}
