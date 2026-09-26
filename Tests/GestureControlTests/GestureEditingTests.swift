import XCTest
@testable import GestureControl

final class GestureEditingTests: XCTestCase {
    @MainActor
    func testManualShortcutCanBeEditedAndSavedAgainWithoutRetraining() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GestureStore(url: directory.appendingPathComponent("gestures.json"))
        let original = SavedGesture(name: "Navigate", binding: .shortcut(
            ShortcutBinding(keyCode: 124, modifiers: 0, title: "→")), samples: [])
        try store.save([original])
        let state = AppState(store: store, startServices: false)
        let editor = ShortcutCapture()
        if case .shortcut(let value) = original.binding { editor.value = value }

        for query in ["left", "right", "up"] {
            let primary = try XCTUnwrap(editor.composer.keys.first { $0.keyCode != nil })
            editor.removeManualKey(primary)
            editor.query = query // Save without first pressing Enter in autocomplete.
            XCTAssertNil(editor.prepareForSave())
            let binding = try XCTUnwrap(editor.value)
            XCTAssertTrue(state.updateGesture(id: original.id, name: "Renamed", binding: .shortcut(binding), enabled: true))
            let reloaded = try XCTUnwrap(store.load().first)
            XCTAssertEqual(reloaded.id, original.id)
            XCTAssertEqual(reloaded.binding, .shortcut(binding))
            XCTAssertEqual(reloaded.name, "Renamed")
            XCTAssertEqual(reloaded.samples.count, original.samples.count)
            XCTAssertFalse(state.training.canSave, "Editing an existing action must not require new training")
        }
        XCTAssertTrue(state.updateGesture(id: original.id, name: "Scroll", binding: .scrollUp, enabled: false))
        let reloaded = try XCTUnwrap(store.load().first)
        XCTAssertEqual(reloaded.binding, .scrollUp)
        XCTAssertFalse(reloaded.enabled)
    }

    @MainActor
    func testPartialDraftKeepsModifiersAndCannotSaveOldShortcut() throws {
        let editor = ShortcutCapture()
        editor.value = ShortcutBinding(keyCode: 124, modifiers: (1 << 20) | (1 << 19), title: "⌥⌘→")
        editor.removeManualKey(try XCTUnwrap(editor.composer.keys.first { $0.keyCode != nil }))
        XCTAssertEqual(editor.composer.keys.count, 2)
        XCTAssertNil(editor.value)
        XCTAssertNotNil(editor.prepareForSave())
        editor.query = "arrow" // Ambiguous: never silently choose a direction.
        XCTAssertNotNil(editor.prepareForSave())
        XCTAssertNil(editor.value)
        editor.query = "left"
        XCTAssertNil(editor.prepareForSave())
        XCTAssertEqual(editor.value?.title, "⌥⌘←")
        XCTAssertEqual(editor.composer.keys.count, 3)
    }

    @MainActor
    func testInvalidPendingTextDoesNotSilentlySavePreviousCombination() {
        let editor = ShortcutCapture()
        editor.value = ShortcutBinding(keyCode: 124, modifiers: 0, title: "→")
        editor.query = "not a key"
        XCTAssertNotNil(editor.prepareForSave())
        editor.value = nil // Changing the selected gesture clears the entire draft.
        XCTAssertTrue(editor.composer.keys.isEmpty)
        XCTAssertTrue(editor.query.isEmpty)
    }

    @MainActor
    func testSaveFailureDoesNotReplaceInMemoryAction() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GestureStore(url: directory.appendingPathComponent("gestures.json"))
        let original = SavedGesture(name: "Existing", binding: .scrollDown, samples: [])
        try store.save([original])
        let state = AppState(store: store, startServices: false)
        try FileManager.default.removeItem(at: store.url)
        try FileManager.default.createDirectory(at: store.url, withIntermediateDirectories: false)
        XCTAssertFalse(state.updateGesture(id: original.id, name: "Changed", binding: .scrollUp, enabled: true))
        XCTAssertEqual(state.gestures.first?.binding, .scrollDown)
        XCTAssertEqual(state.gestures.first?.name, "Existing")
        XCTAssertNotNil(state.message)
        XCTAssertFalse(state.updateGesture(id: UUID(), name: "Missing", binding: .scrollUp, enabled: true))
    }
}
