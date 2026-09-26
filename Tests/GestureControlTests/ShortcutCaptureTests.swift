import AppKit
import XCTest
@testable import GestureControl

final class ShortcutCaptureTests: XCTestCase {
    private func event(code: UInt16 = 124, flags: NSEvent.ModifierFlags = [.command, .option, .numericPad, .function],
                       characters: String = "\u{F703}", type: NSEvent.EventType = .keyDown) -> NSEvent {
        NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: 1,
                        windowNumber: 0, context: nil, characters: characters,
                        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code)!
    }

    func testCommandOptionRightArrowPersistsPhysicalKeyAndOnlyExplicitModifiers() throws {
        let binding = ShortcutBinding.captured(from: event())
        XCTAssertEqual(binding.keyCode, 124)
        XCTAssertEqual(binding.title, "⌥⌘→")
        XCTAssertEqual(binding.modifiers, UInt64(NSEvent.ModifierFlags([.command, .option]).rawValue))
        XCTAssertEqual(CGEventFlags(rawValue: binding.modifiers), [.maskCommand, .maskAlternate])
        XCTAssertEqual(try JSONDecoder().decode(ShortcutBinding.self, from: JSONEncoder().encode(binding)), binding)
    }

    func testArrowsAndFunctionKeysHaveReadableLabels() {
        for (code, label): (UInt16, String) in [(123, "←"), (124, "→"), (125, "↓"), (126, "↑"), (122, "F1"), (49, "Space")] {
            XCTAssertEqual(ShortcutBinding.captured(from: event(code: code, flags: [], characters: "")).title, label)
        }
        XCTAssertEqual(ShortcutBinding.captured(from: event(code: 0, flags: [.control, .shift], characters: "a")).title, "⌃⇧A")
    }

    @MainActor
    func testCommandKeyEquivalentIsCapturedAndConsumed() {
        let capture = ShortcutCapture()
        let view = ShortcutKeyView()
        view.capture = capture
        capture.start()
        XCTAssertTrue(view.performKeyEquivalent(with: event()))
        XCTAssertEqual(capture.value?.keyCode, 124)
        XCTAssertEqual(capture.value?.title, "⌥⌘→")
        XCTAssertFalse(capture.isCapturing)
        XCTAssertFalse(capture.consume(event()))
    }

    @MainActor
    func testEscapeCancelsWithoutReplacingPreviousBinding() {
        let capture = ShortcutCapture()
        let previous = ShortcutBinding.captured(from: event())
        capture.value = previous
        capture.start()
        XCTAssertTrue(capture.consume(event(code: 53, flags: [], characters: "\u{1B}")))
        XCTAssertEqual(capture.value, previous)
        XCTAssertFalse(capture.isCapturing)
    }

    @MainActor
    func testKeyDownRouteAndCancellationWhenAppDeactivates() {
        let capture = ShortcutCapture()
        let view = ShortcutKeyView()
        view.capture = capture
        capture.start()
        view.keyDown(with: event(code: 123))
        XCTAssertEqual(capture.value?.keyCode, 123)
        capture.start()
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil)
        XCTAssertFalse(capture.isCapturing)
        XCTAssertFalse(capture.consume(event()))
        XCTAssertEqual(capture.value?.keyCode, 123)
    }
}
