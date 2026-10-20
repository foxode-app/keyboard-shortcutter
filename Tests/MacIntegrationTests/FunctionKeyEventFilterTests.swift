import CoreGraphics
import ShortcutCore
import XCTest

@testable import KeyboardShortcutter

final class FunctionKeyEventFilterTests: XCTestCase {
    private func event(
        _ code: UInt16 = 101, type: CGEventType = .keyDown,
        flags: CGEventFlags = [], isRepeat: Bool = false, synthetic: Bool = false
    ) throws -> CGEvent {
        let source = try XCTUnwrap(CGEventSource(stateID: .privateState))
        let event = try XCTUnwrap(
            CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: type != .keyUp))
        event.type = type
        event.flags = flags
        event.setIntegerValueField(.keyboardEventAutorepeat, value: isRepeat ? 1 : 0)
        if synthetic { event.setIntegerValueField(.eventSourceUserData, value: shortcutterSyntheticEventTag) }
        return event
    }

    private func rule(keyCode: UInt16 = 101, modifiers: KeyModifiers = []) -> ShortcutRule {
        ShortcutRule(
            name: "F-key mapping",
            trigger: .keyboardShortcut(KeyCombination(keyCode: keyCode, modifiers: modifiers)),
            action: ShortcutAction(kind: "openURL", url: "https://example.com"))
    }

    func testMatchedPressConsumesAllRepeatsAndReleaseEvenAfterModifierChanges() throws {
        var filter = FunctionKeyEventFilter()
        XCTAssertTrue(
            filter.shouldConsume(try event(flags: .maskCommand), type: .keyDown, enabled: true, matched: true)
        )
        XCTAssertTrue(
            filter.shouldConsume(try event(isRepeat: true), type: .keyDown, enabled: true, matched: false))
        XCTAssertTrue(
            filter.shouldConsume(try event(type: .keyUp), type: .keyUp, enabled: true, matched: false))
        XCTAssertFalse(
            filter.shouldConsume(try event(type: .keyUp), type: .keyUp, enabled: true, matched: false))
    }

    func testUnassignedKeysAndNonmatchingModifiersKeepCompleteNativePresses() throws {
        let configured = rule(modifiers: .command)
        for input: KeyboardEvent in [
            KeyboardEvent(kind: .keyDown, keyCode: 109, modifiers: .command),
            KeyboardEvent(kind: .keyDown, keyCode: 101),
        ] {
            var matcher = TriggerMatcher()
            var filter = FunctionKeyEventFilter()
            let matched = !matcher.process(input, rules: [configured]).isEmpty
            XCTAssertFalse(matched)
            XCTAssertFalse(
                filter.shouldConsume(
                    try event(input.keyCode), type: .keyDown, enabled: true, matched: matched))
            XCTAssertFalse(
                filter.shouldConsume(
                    try event(input.keyCode, isRepeat: true), type: .keyDown, enabled: true, matched: false))
            XCTAssertFalse(
                filter.shouldConsume(
                    try event(input.keyCode, type: .keyUp), type: .keyUp, enabled: true, matched: false))
        }
    }

    func testDisabledAndConflictingMappingsDoNotConsumeTheNativeKey() throws {
        var disabled = rule()
        disabled.isEnabled = false
        for rules in [[disabled], [rule(), rule()]] {
            var matcher = TriggerMatcher()
            var filter = FunctionKeyEventFilter()
            let matched = !matcher.process(KeyboardEvent(kind: .keyDown, keyCode: 101), rules: rules).isEmpty
            XCTAssertFalse(matched)
            XCTAssertFalse(filter.shouldConsume(try event(), type: .keyDown, enabled: true, matched: matched))
            XCTAssertFalse(
                filter.shouldConsume(try event(type: .keyUp), type: .keyUp, enabled: true, matched: false))
        }
    }

    func testPausedFilterPassesThroughAndResetDropsOwnership() throws {
        var filter = FunctionKeyEventFilter()
        XCTAssertFalse(filter.shouldConsume(try event(), type: .keyDown, enabled: false, matched: true))
        XCTAssertTrue(filter.shouldConsume(try event(), type: .keyDown, enabled: true, matched: true))
        filter.reset()
        XCTAssertFalse(
            filter.shouldConsume(try event(type: .keyUp), type: .keyUp, enabled: false, matched: false))
        XCTAssertFalse(
            filter.shouldConsume(try event(isRepeat: true), type: .keyDown, enabled: true, matched: false))
        XCTAssertFalse(
            filter.shouldConsume(try event(type: .keyUp), type: .keyUp, enabled: true, matched: false))
    }

    func testRepeatWithoutObservedMatchedDownCannotTakeOwnership() throws {
        var filter = FunctionKeyEventFilter()
        XCTAssertFalse(
            filter.shouldConsume(try event(isRepeat: true), type: .keyDown, enabled: true, matched: true))
        XCTAssertFalse(
            filter.shouldConsume(try event(type: .keyUp), type: .keyUp, enabled: true, matched: false))
    }

    func testFreshUnmatchedPressAfterLostReleaseDoesNotInheritOldOwnership() throws {
        var filter = FunctionKeyEventFilter()
        XCTAssertTrue(filter.shouldConsume(try event(), type: .keyDown, enabled: true, matched: true))
        XCTAssertTrue(filter.shouldConsume(try event(109), type: .keyDown, enabled: true, matched: true))
        filter.releaseOwnership(of: 101)
        XCTAssertFalse(
            filter.shouldConsume(
                try event(flags: .maskCommand), type: .keyDown, enabled: true, matched: false))
        XCTAssertFalse(
            filter.shouldConsume(try event(type: .keyUp), type: .keyUp, enabled: true, matched: false))
        XCTAssertTrue(
            filter.shouldConsume(try event(109, type: .keyUp), type: .keyUp, enabled: true, matched: false))
    }

    func testSyntheticEventsBypassWithoutReleasingPhysicalOwnership() throws {
        var filter = FunctionKeyEventFilter()
        XCTAssertFalse(
            filter.shouldConsume(try event(synthetic: true), type: .keyDown, enabled: true, matched: true))
        XCTAssertTrue(filter.shouldConsume(try event(), type: .keyDown, enabled: true, matched: true))
        XCTAssertFalse(
            filter.shouldConsume(
                try event(type: .keyUp, synthetic: true), type: .keyUp, enabled: true, matched: false))
        XCTAssertTrue(
            filter.shouldConsume(try event(type: .keyUp), type: .keyUp, enabled: true, matched: false))
    }

    func testMatchingOrdinaryKeysAreNeverConsumedByTheFunctionKeyFilter() throws {
        var filter = FunctionKeyEventFilter()
        XCTAssertFalse(filter.shouldConsume(try event(40), type: .keyDown, enabled: true, matched: true))
        XCTAssertFalse(
            filter.shouldConsume(try event(40, type: .keyUp), type: .keyUp, enabled: true, matched: false))
        XCTAssertFalse(
            filter.shouldConsume(
                try event(58, type: .flagsChanged), type: .flagsChanged, enabled: true, matched: true))
    }

    func testSimultaneousMappedKeysHaveIndependentReleases() throws {
        var filter = FunctionKeyEventFilter()
        for key: UInt16 in [101, 109] {
            XCTAssertTrue(filter.shouldConsume(try event(key), type: .keyDown, enabled: true, matched: true))
        }
        XCTAssertTrue(
            filter.shouldConsume(try event(101, type: .keyUp), type: .keyUp, enabled: true, matched: false))
        XCTAssertTrue(
            filter.shouldConsume(
                try event(109, isRepeat: true), type: .keyDown, enabled: true, matched: false))
        XCTAssertTrue(
            filter.shouldConsume(try event(109, type: .keyUp), type: .keyUp, enabled: true, matched: false))
    }

    @MainActor
    func testIntrinsicFnFlagMatchesBareFunctionKeyButPhysicalFnRemainsDistinct() throws {
        let event = try event(flags: .maskSecondaryFn)
        let bare = rule()
        let withFn = rule(modifiers: .function)
        for physicalFnDown in [false, true] {
            var matcher = TriggerMatcher()
            let modifiers = EventMonitor.modifiers(from: event.flags, physicalFunctionDown: physicalFnDown)
            let matched = matcher.process(
                KeyboardEvent(kind: .keyDown, keyCode: 101, modifiers: modifiers), rules: [bare, withFn])
            XCTAssertEqual(matched.map(\.id), [physicalFnDown ? withFn.id : bare.id])
        }
    }

    @MainActor
    func testOptionMappingMatchesBeforeOptionFilterAndUnassignedKeyStillLosesOption() throws {
        var matcher = TriggerMatcher()
        var filter = FunctionKeyEventFilter()
        let optionFilter = OptionEventFilter()
        let configured = rule(modifiers: .option)
        let original = try event(flags: [.maskAlternate, .maskSecondaryFn])
        let modifiers = EventMonitor.modifiers(from: original.flags, physicalFunctionDown: false)
        let matched = !matcher.process(
            KeyboardEvent(kind: .keyDown, keyCode: 101, modifiers: modifiers), rules: [configured]
        ).isEmpty
        XCTAssertTrue(filter.shouldConsume(original, type: .keyDown, enabled: true, matched: matched))
        let unassigned = try event(109, flags: .maskAlternate)
        XCTAssertFalse(filter.shouldConsume(unassigned, type: .keyDown, enabled: true, matched: false))
        let forwarded = try XCTUnwrap(optionFilter.apply(to: unassigned, type: .keyDown, enabled: true))
        XCTAssertFalse(forwarded.flags.contains(.maskAlternate))
        XCTAssertEqual(forwarded.getIntegerValueField(.keyboardEventKeycode), 109)
    }
}
