import AppKit
import XCTest
@testable import Minute

@MainActor
final class ShortcutRecognizerTests: XCTestCase {
    private let option = NSEvent.ModifierFlags.option.rawValue
    private let leftOption: UInt = 0x000020
    private let rightOption: UInt = 0x000040

    func testDoubleOptionTriggersAfterTwoDistinctPresses() {
        var recognizer = ShortcutRecognizer()

        XCTAssertFalse(recognizer.consume(input(.flagsChanged, at: 1.0, flags: option), mode: .doubleOption))
        XCTAssertFalse(recognizer.consume(input(.flagsChanged, at: 1.1, flags: 0), mode: .doubleOption))
        XCTAssertTrue(recognizer.consume(input(.flagsChanged, at: 1.2, flags: option), mode: .doubleOption))
    }

    func testHeldOptionDoesNotTriggerTwice() {
        var recognizer = ShortcutRecognizer()

        XCTAssertFalse(recognizer.consume(input(.flagsChanged, at: 1.0, flags: option), mode: .doubleOption))
        XCTAssertFalse(recognizer.consume(input(.flagsChanged, at: 1.1, flags: option | leftOption | rightOption), mode: .doubleOption))
    }

    func testKeyDownInterruptsDoubleOptionSequence() {
        var recognizer = ShortcutRecognizer()

        XCTAssertFalse(recognizer.consume(input(.flagsChanged, at: 1.0, flags: option), mode: .doubleOption))
        XCTAssertFalse(recognizer.consume(input(.flagsChanged, at: 1.1, flags: 0), mode: .doubleOption))
        XCTAssertFalse(recognizer.consume(input(.keyDown, at: 1.15, flags: 0), mode: .doubleOption))
        XCTAssertFalse(recognizer.consume(input(.flagsChanged, at: 1.2, flags: option), mode: .doubleOption))
    }

    func testBothOptionsTriggersOncePerChord() {
        var recognizer = ShortcutRecognizer()
        let both = option | leftOption | rightOption

        XCTAssertTrue(recognizer.consume(input(.flagsChanged, at: 1.0, flags: both), mode: .bothOptions))
        XCTAssertFalse(recognizer.consume(input(.flagsChanged, at: 1.1, flags: both), mode: .bothOptions))
        XCTAssertFalse(recognizer.consume(input(.flagsChanged, at: 1.2, flags: 0), mode: .bothOptions))
        XCTAssertTrue(recognizer.consume(input(.flagsChanged, at: 1.3, flags: both), mode: .bothOptions))
    }

    private func input(
        _ kind: ShortcutInput.Kind,
        at timestamp: TimeInterval,
        flags: UInt
    ) -> ShortcutInput {
        ShortcutInput(kind: kind, timestamp: timestamp, modifierFlags: flags)
    }
}
