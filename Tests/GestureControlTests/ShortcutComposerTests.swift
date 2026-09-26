import AppKit
import XCTest
@testable import GestureControl

final class ShortcutComposerTests: XCTestCase {
    private let right = ShortcutKey.key(124, "Right Arrow", label: "→", aliases: ["right"])
    private let left = ShortcutKey.key(123, "Left Arrow", label: "←", aliases: ["left"])
    private var catalog: [ShortcutKey] { ShortcutKey.modifiers + [right, left, .key(0, "A"), .key(122, "F1")] }

    func testAutocompleteBuildsCommandAltRightAndPersistsIt() throws {
        var composer = ShortcutComposer()
        for query in ["cmd", "alt", "right"] {
            let suggested = try XCTUnwrap(composer.suggestions(for: query, catalog: catalog).first)
            composer.add(suggested)
        }
        let binding = try XCTUnwrap(composer.binding)
        XCTAssertEqual(composer.keys.count, 3)
        XCTAssertEqual(binding.title, "⌥⌘→")
        XCTAssertEqual(binding.keyCode, 124)
        XCTAssertEqual(CGEventFlags(rawValue: binding.modifiers), [.maskCommand, .maskAlternate])
        XCTAssertEqual(try JSONDecoder().decode(ShortcutBinding.self, from: JSONEncoder().encode(binding)), binding)
    }

    func testFourKeyShortcutPersistsAllThreeModifiers() throws {
        var composer = ShortcutComposer()
        for query in ["cmd", "alt", "shift", "right"] {
            composer.add(try XCTUnwrap(composer.suggestions(for: query, catalog: catalog).first))
        }
        let binding = try XCTUnwrap(composer.binding)
        XCTAssertEqual(composer.keys.count, 4)
        XCTAssertEqual(binding.title, "⌥⇧⌘→")
        XCTAssertEqual(CGEventFlags(rawValue: binding.modifiers), [.maskCommand, .maskAlternate, .maskShift])
        let decoded = try JSONDecoder().decode(ShortcutBinding.self, from: JSONEncoder().encode(binding))
        var reloaded = ShortcutComposer()
        reloaded.load(decoded, catalog: catalog)
        XCTAssertEqual(reloaded.binding, binding)
    }

    func testNoDuplicateFifthKeyOrSecondPrimaryKey() {
        var composer = ShortcutComposer()
        composer.add(right)
        composer.add(left)
        composer.add(right)
        XCTAssertEqual(composer.keys.count, 1)
        composer.add(ShortcutKey.modifiers[0])
        composer.add(ShortcutKey.modifiers[1])
        composer.add(ShortcutKey.modifiers[2])
        composer.add(ShortcutKey.modifiers[3])
        XCTAssertEqual(composer.keys.count, 4)
        XCTAssertTrue(composer.suggestions(for: "", catalog: catalog).isEmpty)
    }

    func testReserveSlotForPrimaryAndRejectIncompleteCombination() {
        var composer = ShortcutComposer()
        for modifier in ShortcutKey.modifiers { composer.add(modifier) }
        XCTAssertEqual(composer.keys.count, 3)
        XCTAssertNil(composer.binding)
        XCTAssertTrue(composer.suggestions(for: "", catalog: catalog).allSatisfy { $0.keyCode != nil })
        composer.add(right)
        XCTAssertNotNil(composer.binding)
        composer.keys.removeAll { $0.keyCode != nil }
        XCTAssertNil(composer.binding)
        composer.add(left)
        XCTAssertEqual(composer.binding?.keyCode, 123)
    }

    func testLoadRecordedShortcutWithoutTruncatingLegacyModifiers() {
        var composer = ShortcutComposer()
        let allFlags = NSEvent.ModifierFlags([.command, .control, .shift, .option])
        composer.load(ShortcutBinding(keyCode: 124, modifiers: UInt64(allFlags.rawValue), title: "Legacy"), catalog: catalog)
        XCTAssertEqual(composer.keys.count, 5)
        XCTAssertNil(composer.binding)
        composer.keys.removeAll { $0.id == "control" || $0.id == "shift" }
        XCTAssertEqual(composer.binding?.title, "⌥⌘→")
        composer.load(nil, catalog: catalog)
        XCTAssertTrue(composer.keys.isEmpty)
    }

    func testSearchPrioritizesExactNamesAndHandlesCaseAndWhitespace() {
        let composer = ShortcutComposer()
        XCTAssertEqual(composer.suggestions(for: " a ", catalog: catalog).first?.keyCode, 0)
        XCTAssertEqual(composer.suggestions(for: "CMD", catalog: catalog).first?.id, "command")
        XCTAssertEqual(composer.suggestions(for: "→", catalog: catalog).first?.keyCode, 124)
        XCTAssertTrue(composer.suggestions(for: "not a key", catalog: catalog).isEmpty)
    }

    @MainActor
    func testCurrentKeyboardCatalogContainsUniquePhysicalKeysAndNamedKeys() {
        let keys = ShortcutKey.catalog()
        XCTAssertEqual(Set(keys.map(\.id)).count, keys.count)
        XCTAssertTrue(keys.allSatisfy { !$0.name.isEmpty })
        XCTAssertEqual(keys.first { $0.keyCode == 124 }?.label, "→")
        XCTAssertEqual(keys.first { $0.keyCode == 111 }?.name, "F12")
        XCTAssertNotNil(keys.first { $0.keyCode == 0 })
    }
}
