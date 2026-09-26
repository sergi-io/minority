import XCTest
import ApplicationServices
@testable import GestureControl

final class TextActionTests: XCTestCase {
    func testUnicodeEventsPreserveTextAndNeverSplitSurrogates() {
        let text = "  Hello, señor 👋🏽!\n" + String(repeating: "a", count: 19) + "🌍 café e\u{301}\tDone.  "
        let events = SystemActionEmitter.textEvents(for: text)
        XCTAssertEqual(events.count % 2, 0)
        var reconstructed: [UInt16] = []
        for index in stride(from: 0, to: events.count, by: 2) {
            let down = events[index], up = events[index + 1]
            XCTAssertEqual(down.type, .keyDown)
            XCTAssertEqual(up.type, .keyUp)
            XCTAssertEqual(down.flags, [])
            XCTAssertEqual(up.flags, [])
            let units = payload(down)
            XCTAssertFalse(units.isEmpty)
            XCTAssertLessThanOrEqual(units.count, 20)
            XCTAssertFalse((0xDC00...0xDFFF).contains(units.first!))
            XCTAssertFalse((0xD800...0xDBFF).contains(units.last!))
            XCTAssertEqual(units, payload(up))
            reconstructed.append(contentsOf: units)
        }
        XCTAssertEqual(reconstructed, Array(text.utf16))
        XCTAssertTrue(SystemActionEmitter.textEvents(for: "").isEmpty)
    }

    func testLibraryPreservesTextAlongsideExistingActions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GestureStore(url: directory.appendingPathComponent("gestures.json"))
        let bindings: [GestureBinding] = [.scrollDown, .scrollUp, .browserBack,
            .shortcut(ShortcutBinding(keyCode: 124, modifiers: 1 << 20, title: "⌘→")),
            .text("  Hola, mundo 👋\nSecond line.  ")]
        let gestures = bindings.enumerated().map { SavedGesture(name: "Action \($0.offset)", binding: $0.element, samples: []) }
        try store.save(gestures)
        XCTAssertEqual(try store.load(), gestures)
        XCTAssertEqual(try JSONDecoder().decode(GestureBinding.self, from: Data(#"{"scrollDown":{}}"#.utf8)), .scrollDown)
    }

    @MainActor
    func testEditingTextPersistsWithoutTrimmingAndRejectsEmptyText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = GestureStore(url: directory.appendingPathComponent("gestures.json"))
        let original = SavedGesture(name: "Write", binding: .scrollDown, samples: [])
        try store.save([original])
        let state = AppState(store: store, startServices: false)
        for text in ["Hello", "  Thank you!\nSaludos 👋  ", " "] {
            XCTAssertTrue(state.updateGesture(id: original.id, name: original.name, binding: .text(text), enabled: true))
            XCTAssertEqual(try store.load().first?.binding, .text(text))
        }
        XCTAssertFalse(state.updateGesture(id: original.id, name: original.name, binding: .text(""), enabled: true))
        XCTAssertEqual(try store.load().first?.binding, .text(" "))
        XCTAssertEqual(state.gestures.first?.id, original.id)
    }

    private func payload(_ event: CGEvent) -> [UInt16] {
        var length = 0
        var units = [UInt16](repeating: 0, count: 32)
        event.keyboardGetUnicodeString(maxStringLength: units.count, actualStringLength: &length, unicodeString: &units)
        return Array(units.prefix(length))
    }
}
