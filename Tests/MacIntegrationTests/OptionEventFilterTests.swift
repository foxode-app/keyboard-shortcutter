import AppKit
import CoreGraphics
import ShortcutCore
import XCTest

@testable import KeyboardShortcutter

final class OptionEventFilterTests: XCTestCase {
    private let filter = OptionEventFilter()
    private let optionFlags = CGEventFlags(rawValue: CGEventFlags.maskAlternate.rawValue | 0x20 | 0x40)

    func testDisabledFilterLeavesOptionTransitionUntouched() throws {
        let event = try keyboardEvent(code: 58, type: .flagsChanged, flags: optionFlags)
        let result = try XCTUnwrap(filter.apply(to: event, type: event.type, enabled: false))
        XCTAssertTrue(result === event)
        XCTAssertEqual(result.flags, optionFlags)
    }

    func testBothOptionPressAndReleaseTransitionsAreConsumed() throws {
        for code: UInt16 in [58, 61] {
            for flags: CGEventFlags in [optionFlags, []] {
                let event = try keyboardEvent(code: code, type: .flagsChanged, flags: flags)
                XCTAssertNil(try filter.apply(to: event, type: event.type, enabled: true))
            }
        }
    }

    func testOptionReleaseWithOtherOptionHeldIsConsumed() throws {
        let rightOption: CGEventFlags = [.maskAlternate, CGEventFlags(rawValue: 0x40)]
        let event = try keyboardEvent(code: 58, type: .flagsChanged, flags: rightOption)
        XCTAssertNil(try filter.apply(to: event, type: event.type, enabled: true))
    }

    func testOptionPressWithOtherModifiersDoesNotLeakAnOptionTransition() throws {
        let event = try keyboardEvent(code: 61, type: .flagsChanged, flags: optionFlags.union(.maskCommand))
        XCTAssertNil(try filter.apply(to: event, type: event.type, enabled: true))
    }

    func testOtherModifierTransitionsPreserveTheirOwnDeviceBits() throws {
        let expected = CGEventFlags(rawValue: CGEventFlags.maskShift.rawValue | 0x02)
        let event = try keyboardEvent(code: 56, type: .flagsChanged, flags: optionFlags.union(expected))
        let result = try XCTUnwrap(filter.apply(to: event, type: event.type, enabled: true))
        XCTAssertTrue(result === event)
        XCTAssertEqual(result.flags, expected)
        XCTAssertEqual(result.getIntegerValueField(.keyboardEventKeycode), 56)
    }

    func testKeyboardReplacementPreservesEveryNonOptionFlag() throws {
        let expected: CGEventFlags = [
            .maskCommand, .maskShift, .maskControl, .maskAlphaShift,
            .maskSecondaryFn, .maskNumericPad, .maskNonCoalesced,
            CGEventFlags(rawValue: 0x01 | 0x02 | 0x08),
        ]
        let event = try keyboardEvent(code: 40, type: .keyDown, flags: optionFlags.union(expected))
        let result = try XCTUnwrap(filter.apply(to: event, type: event.type, enabled: true))
        XCTAssertFalse(result === event)
        XCTAssertEqual(result.flags, expected)
        // The matcher receives the original physical event before any outgoing transformation.
        XCTAssertEqual(event.flags, optionFlags.union(expected))
    }

    func testDeviceOptionBitsAreClearedEvenWithoutAggregateOptionFlag() throws {
        let event = try keyboardEvent(code: 40, type: .keyDown, flags: CGEventFlags(rawValue: 0x20 | 0x40))
        let result = try XCTUnwrap(filter.apply(to: event, type: event.type, enabled: true))
        XCTAssertTrue(result.flags.isEmpty)
    }

    func testKeycodeRepeatTimingAndSourceMetadataSurviveReplacement() throws {
        for type: CGEventType in [.keyDown, .keyUp] {
            let event = try keyboardEvent(code: 40, type: type, flags: optionFlags)
            event.timestamp = 123_456_789
            event.location = CGPoint(x: 15, y: 25)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 1)
            event.setIntegerValueField(.keyboardEventKeyboardType, value: 42)
            event.setIntegerValueField(.eventSourceUserData, value: 12345)
            let result = try XCTUnwrap(filter.apply(to: event, type: type, enabled: true))
            XCTAssertEqual(result.type, type)
            XCTAssertEqual(result.timestamp, event.timestamp)
            XCTAssertEqual(result.location, event.location)
            for field: CGEventField in [
                .keyboardEventKeycode, .keyboardEventAutorepeat, .keyboardEventKeyboardType,
                .eventSourceUserData, .eventSourceUnixProcessID, .eventSourceStateID,
            ] {
                XCTAssertEqual(result.getIntegerValueField(field), event.getIntegerValueField(field))
            }
        }
    }

    func testKeyWithoutOptionKeepsItsOriginalPayloadAndIdentity() throws {
        let event = try keyboardEvent(code: 14, type: .keyDown, flags: .maskShift)
        setUnicode([0x0045], on: event)
        let result = try XCTUnwrap(filter.apply(to: event, type: event.type, enabled: true))
        XCTAssertTrue(result === event)
        XCTAssertEqual(unicode(of: result), [0x0045])
    }

    func testTranslatedOptionUnicodeIsReplacedByPlainKeycodeTranslation() throws {
        // All character data here is fabricated test input; production never reads Unicode.
        let event = try keyboardEvent(code: 14, type: .keyDown, flags: optionFlags)
        setUnicode([0x00B4], on: event)
        let result = try XCTUnwrap(filter.apply(to: event, type: event.type, enabled: true))
        let ordinary = try keyboardEvent(code: 14, type: .keyDown, flags: [])
        XCTAssertEqual(unicode(of: result), unicode(of: ordinary))
        XCTAssertEqual(unicode(of: event), [0x00B4])
    }

    func testShiftSurvivesRemovalOfOptionCharacterTranslation() throws {
        let event = try keyboardEvent(code: 0, type: .keyDown, flags: optionFlags.union(.maskShift))
        setUnicode([0x00C5], on: event)
        let result = try XCTUnwrap(filter.apply(to: event, type: event.type, enabled: true))
        let ordinary = try keyboardEvent(code: 0, type: .keyDown, flags: .maskShift)
        XCTAssertEqual(result.flags, .maskShift)
        XCTAssertEqual(unicode(of: result), unicode(of: ordinary))
    }

    func testAppKitTranslatesRebuiltOptionDeadKeysAsOrdinaryKeys() throws {
        for remainingFlags: CGEventFlags in [[], .maskShift] {
            let event = try keyboardEvent(code: 14, type: .keyDown, flags: optionFlags.union(remainingFlags))
            setUnicode([0x00B4], on: event)
            let result = try XCTUnwrap(filter.apply(to: event, type: event.type, enabled: true))
            let ordinary = try keyboardEvent(code: 14, type: .keyDown, flags: remainingFlags)
            let rebuiltCharacters = try XCTUnwrap(NSEvent(cgEvent: result)?.characters)
            XCTAssertEqual(rebuiltCharacters, NSEvent(cgEvent: ordinary)?.characters)
            XCTAssertFalse(rebuiltCharacters.isEmpty)
        }
    }

    func testTaggedSyntheticOptionEventsBypassTheFilter() throws {
        for type: CGEventType in [.keyDown, .keyUp, .flagsChanged] {
            let event = try keyboardEvent(
                code: type == .flagsChanged ? 58 : 14, type: type, flags: optionFlags)
            event.setIntegerValueField(.eventSourceUserData, value: shortcutterSyntheticEventTag)
            setUnicode([0x1234], on: event)
            let result = try XCTUnwrap(filter.apply(to: event, type: type, enabled: true))
            XCTAssertTrue(result === event)
            XCTAssertEqual(result.flags, optionFlags)
            XCTAssertEqual(unicode(of: result), [0x1234])
        }
    }

    func testMouseClicksMotionAndDraggingPreserveTheirPayload() throws {
        for type: CGEventType in [
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .mouseMoved,
            .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        ] {
            let event = try XCTUnwrap(
                CGEvent(
                    mouseEventSource: nil, mouseType: type, mouseCursorPosition: CGPoint(x: 42, y: 84),
                    mouseButton: .left))
            event.flags = optionFlags.union(.maskCommand)
            event.setIntegerValueField(.mouseEventClickState, value: 2)
            event.setIntegerValueField(.mouseEventDeltaX, value: 7)
            let result = try XCTUnwrap(filter.apply(to: event, type: type, enabled: true))
            XCTAssertTrue(result === event)
            XCTAssertEqual(result.flags, .maskCommand)
            XCTAssertEqual(result.type, type)
            XCTAssertEqual(result.location, CGPoint(x: 42, y: 84))
            XCTAssertEqual(result.getIntegerValueField(.mouseEventClickState), 2)
            XCTAssertEqual(result.getIntegerValueField(.mouseEventDeltaX), 7)
        }
    }

    func testScrollingPreservesDeltaAndPhase() throws {
        let event = try XCTUnwrap(
            CGEvent(
                scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 12, wheel2: -7, wheel3: 0)
        )
        event.flags = optionFlags.union(.maskShift)
        event.setIntegerValueField(.scrollWheelEventScrollPhase, value: 2)
        let fields: [CGEventField] = [
            .scrollWheelEventDeltaAxis1, .scrollWheelEventDeltaAxis2,
            .scrollWheelEventPointDeltaAxis1, .scrollWheelEventPointDeltaAxis2,
            .scrollWheelEventScrollPhase,
        ]
        let before = fields.map { event.getIntegerValueField($0) }
        let result = try XCTUnwrap(filter.apply(to: event, type: .scrollWheel, enabled: true))
        XCTAssertTrue(result === event)
        XCTAssertEqual(result.flags, .maskShift)
        XCTAssertEqual(fields.map { result.getIntegerValueField($0) }, before)
    }

    @MainActor
    func testPhysicalOptionShortcutMatchesBeforeOutgoingOptionIsRemoved() throws {
        let rule = ShortcutRule(
            name: "Physical Option K",
            trigger: .keyboardShortcut(KeyCombination(keyCode: 40, modifiers: .option)),
            action: ShortcutAction(kind: "openURL", url: "https://example.com"))
        let original = try keyboardEvent(code: 40, type: .keyDown, flags: optionFlags)
        var matcher = TriggerMatcher()
        let input = KeyboardEvent(
            kind: .keyDown, keyCode: 40, modifiers: EventMonitor.modifiers(from: original.flags))
        XCTAssertEqual(matcher.process(input, rules: [rule]).map(\.id), [rule.id])
        let result = try XCTUnwrap(filter.apply(to: original, type: .keyDown, enabled: true))
        XCTAssertTrue(result.flags.isEmpty)
        XCTAssertEqual(matcher.process(input, rules: [rule]).count, 0)
    }

    private func keyboardEvent(code: UInt16, type: CGEventType, flags: CGEventFlags) throws -> CGEvent {
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: type != .keyUp))
        event.type = type
        event.flags = flags
        return event
    }

    private func setUnicode(_ characters: [UniChar], on event: CGEvent) {
        characters.withUnsafeBufferPointer {
            event.keyboardSetUnicodeString(stringLength: $0.count, unicodeString: $0.baseAddress)
        }
    }

    private func unicode(of event: CGEvent) -> [UniChar] {
        var length = 0
        var characters = [UniChar](repeating: 0, count: 16)
        event.keyboardGetUnicodeString(
            maxStringLength: characters.count, actualStringLength: &length, unicodeString: &characters)
        return Array(characters.prefix(length))
    }
}
