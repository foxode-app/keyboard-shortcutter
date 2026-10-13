import XCTest

@testable import ShortcutCore

final class TriggerMatcherTests: XCTestCase {
    private func tapRule(_ modifier: PhysicalModifier, enabled: Bool = true) -> ShortcutRule {
        ShortcutRule(
            name: modifier.title, trigger: .modifierTap(modifier),
            action: ShortcutAction(kind: "inputSource", inputSourceID: "test.input"), isEnabled: enabled
        )
    }

    private func shortcutRule(_ modifiers: KeyModifiers = [.control, .option]) -> ShortcutRule {
        ShortcutRule(
            name: "Example", trigger: .keyboardShortcut(KeyCombination(keyCode: 40, modifiers: modifiers)),
            action: ShortcutAction(kind: "openURL", url: "https://example.com")
        )
    }

    func testLeftAndRightPhysicalModifierCodesAreDistinct() {
        let expected: [(PhysicalModifier, UInt16)] = [
            (.leftOption, 58), (.rightOption, 61), (.leftCommand, 55), (.rightCommand, 54),
            (.leftControl, 59), (.rightControl, 62), (.leftShift, 56), (.rightShift, 60),
        ]
        for (modifier, code) in expected {
            XCTAssertEqual(modifier.keyCode, code)
            XCTAssertEqual(PhysicalModifier(keyCode: code), modifier)
        }
        XCTAssertEqual(Set(expected.map(\.1)).count, PhysicalModifier.allCases.count)
        XCTAssertNil(PhysicalModifier(keyCode: 57), "Caps Lock cannot be a reliable physical-release trigger")
        XCTAssertNil(PhysicalModifier(keyCode: 40))
    }

    func testEachModifierFiresOnlyItsOwnRuleOnRelease() {
        let rules = PhysicalModifier.allCases.map { tapRule($0) }
        var matcher = TriggerMatcher()
        for (index, modifier) in PhysicalModifier.allCases.enumerated() {
            XCTAssertTrue(
                matcher.process(
                    KeyboardEvent(
                        kind: .modifierDown, keyCode: modifier.keyCode, modifiers: modifier.logicalModifier),
                    rules: rules
                ).isEmpty)
            XCTAssertEqual(
                matcher.process(
                    KeyboardEvent(kind: .modifierUp, keyCode: modifier.keyCode), rules: rules
                ).map(\.id), [rules[index].id])
        }
    }

    func testModifierPlusKeyDoesNotFireTapWithEitherReleaseOrder() {
        let rule = tapRule(.leftOption)
        for releaseModifierFirst in [false, true] {
            var matcher = TriggerMatcher()
            _ = matcher.process(
                KeyboardEvent(kind: .modifierDown, keyCode: 58, modifiers: .option), rules: [rule])
            XCTAssertTrue(
                matcher.process(KeyboardEvent(kind: .keyDown, keyCode: 40, modifiers: .option), rules: [rule])
                    .isEmpty)
            let modifierRelease = KeyboardEvent(kind: .modifierUp, keyCode: 58)
            let keyRelease = KeyboardEvent(kind: .keyUp, keyCode: 40)
            let releases =
                releaseModifierFirst ? [modifierRelease, keyRelease] : [keyRelease, modifierRelease]
            for event in releases { XCTAssertTrue(matcher.process(event, rules: [rule]).isEmpty) }
        }
    }

    func testModifierPressedWhileKeyHeldDoesNotBecomeTap() {
        let rule = tapRule(.leftOption)
        var matcher = TriggerMatcher()
        _ = matcher.process(KeyboardEvent(kind: .keyDown, keyCode: 40), rules: [rule])
        _ = matcher.process(
            KeyboardEvent(kind: .modifierDown, keyCode: 58, modifiers: .option), rules: [rule])
        _ = matcher.process(KeyboardEvent(kind: .keyUp, keyCode: 40), rules: [rule])
        XCTAssertTrue(matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 58), rules: [rule]).isEmpty)
    }

    func testMouseActivityCancelsModifierTap() {
        let rule = tapRule(.leftOption)
        var matcher = TriggerMatcher()
        _ = matcher.process(
            KeyboardEvent(kind: .modifierDown, keyCode: 58, modifiers: .option), rules: [rule])
        _ = matcher.process(KeyboardEvent(kind: .mouseActivity), rules: [rule])
        XCTAssertTrue(matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 58), rules: [rule]).isEmpty)
    }

    func testLongHoldHasNoTimeoutAndFiresOnRelease() {
        let rule = tapRule(.rightOption)
        var matcher = TriggerMatcher()
        _ = matcher.process(
            KeyboardEvent(kind: .modifierDown, keyCode: 61, modifiers: .option), rules: [rule])
        // No timer or wall-clock threshold is consulted, so any quiet duration is valid.
        XCTAssertEqual(matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 61), rules: [rule]), [rule])
    }

    func testSimultaneousDifferentModifiersCancelBothTaps() {
        let rules = [tapRule(.leftOption), tapRule(.leftShift)]
        var matcher = TriggerMatcher()
        _ = matcher.process(KeyboardEvent(kind: .modifierDown, keyCode: 58, modifiers: .option), rules: rules)
        _ = matcher.process(
            KeyboardEvent(kind: .modifierDown, keyCode: 56, modifiers: [.option, .shift]), rules: rules)
        XCTAssertTrue(
            matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 56, modifiers: .option), rules: rules)
                .isEmpty)
        XCTAssertTrue(matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 58), rules: rules).isEmpty)
    }

    func testSimultaneousLeftAndRightSameModifierCancelBothTaps() {
        let rules = [tapRule(.leftOption), tapRule(.rightOption)]
        var matcher = TriggerMatcher()
        _ = matcher.process(KeyboardEvent(kind: .modifierDown, keyCode: 58, modifiers: .option), rules: rules)
        _ = matcher.process(KeyboardEvent(kind: .modifierDown, keyCode: 61, modifiers: .option), rules: rules)
        XCTAssertTrue(
            matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 58, modifiers: .option), rules: rules)
                .isEmpty)
        XCTAssertTrue(matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 61), rules: rules).isEmpty)
    }

    func testDuplicateModifierEventsAndReleasesFireOnce() {
        let rule = tapRule(.leftCommand)
        var matcher = TriggerMatcher()
        let press = KeyboardEvent(kind: .modifierDown, keyCode: 55, modifiers: .command)
        let release = KeyboardEvent(kind: .modifierUp, keyCode: 55)
        _ = matcher.process(press, rules: [rule])
        _ = matcher.process(press, rules: [rule])
        XCTAssertEqual(matcher.process(release, rules: [rule]), [rule])
        XCTAssertTrue(matcher.process(release, rules: [rule]).isEmpty)
    }

    func testRepeatedKeyboardShortcutFiresOnceUntilKeyUp() {
        let rule = shortcutRule()
        var matcher = TriggerMatcher()
        let press = KeyboardEvent(kind: .keyDown, keyCode: 40, modifiers: [.control, .option])
        XCTAssertEqual(matcher.process(press, rules: [rule]), [rule])
        XCTAssertTrue(matcher.process(press, rules: [rule]).isEmpty)
        XCTAssertTrue(
            matcher.process(
                KeyboardEvent(kind: .keyDown, keyCode: 40, modifiers: [.control, .option], isRepeat: true),
                rules: [rule]
            ).isEmpty)
        _ = matcher.process(KeyboardEvent(kind: .keyUp, keyCode: 40), rules: [rule])
        XCTAssertEqual(matcher.process(press, rules: [rule]), [rule])
    }

    func testFirstObservedAutoRepeatDoesNotFire() {
        let rule = shortcutRule()
        var matcher = TriggerMatcher()
        XCTAssertTrue(
            matcher.process(
                KeyboardEvent(kind: .keyDown, keyCode: 40, modifiers: [.control, .option], isRepeat: true),
                rules: [rule]
            ).isEmpty)
        XCTAssertTrue(
            matcher.process(
                KeyboardEvent(kind: .keyDown, keyCode: 40, modifiers: [.control, .option]), rules: [rule]
            ).isEmpty)
    }

    func testShortcutRequiresExactLogicalModifiers() {
        let rule = shortcutRule()
        for modifiers: KeyModifiers in [[], [.control], [.control, .option, .shift]] {
            var matcher = TriggerMatcher()
            XCTAssertTrue(
                matcher.process(
                    KeyboardEvent(kind: .keyDown, keyCode: 40, modifiers: modifiers), rules: [rule]
                ).isEmpty)
        }
        var matcher = TriggerMatcher()
        XCTAssertEqual(
            matcher.process(
                KeyboardEvent(kind: .keyDown, keyCode: 40, modifiers: [.control, .option]), rules: [rule]
            ), [rule])
    }

    func testDisabledRulesNeverFireOrConflict() {
        let disabled = tapRule(.leftOption, enabled: false)
        let enabled = tapRule(.leftOption)
        XCTAssertTrue(TriggerMatcher.conflicts(in: [disabled, enabled]).isEmpty)
        var matcher = TriggerMatcher()
        _ = matcher.process(KeyboardEvent(kind: .modifierDown, keyCode: 58), rules: [disabled])
        XCTAssertTrue(
            matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 58), rules: [disabled]).isEmpty)
    }

    func testConflictingTapRulesAreReportedAndSuppressed() {
        let rules = [tapRule(.leftOption), tapRule(.leftOption)]
        let conflicts = TriggerMatcher.conflicts(in: rules)
        XCTAssertEqual(conflicts.count, 1)
        XCTAssertEqual(conflicts[0].ruleIDs, rules.map(\.id))
        var matcher = TriggerMatcher()
        _ = matcher.process(KeyboardEvent(kind: .modifierDown, keyCode: 58), rules: rules)
        XCTAssertTrue(matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 58), rules: rules).isEmpty)
    }

    func testConflictingKeyboardRulesAreSuppressed() {
        let rules = [shortcutRule(), shortcutRule()]
        XCTAssertEqual(TriggerMatcher.conflicts(in: rules).count, 1)
        var matcher = TriggerMatcher()
        XCTAssertTrue(
            matcher.process(
                KeyboardEvent(kind: .keyDown, keyCode: 40, modifiers: [.control, .option]), rules: rules
            ).isEmpty)
    }

    func testTapAndShortcutWithSameModifierDoNotConflict() {
        let rules = [tapRule(.leftOption), shortcutRule(.option)]
        XCTAssertTrue(TriggerMatcher.conflicts(in: rules).isEmpty)
        var matcher = TriggerMatcher()
        _ = matcher.process(KeyboardEvent(kind: .modifierDown, keyCode: 58, modifiers: .option), rules: rules)
        XCTAssertEqual(
            matcher.process(KeyboardEvent(kind: .keyDown, keyCode: 40, modifiers: .option), rules: rules),
            [rules[1]])
        _ = matcher.process(KeyboardEvent(kind: .keyUp, keyCode: 40, modifiers: .option), rules: rules)
        XCTAssertTrue(matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 58), rules: rules).isEmpty)
    }

    func testResetPreventsStaleTapAndReleasesHeldKeys() {
        let tap = tapRule(.leftOption)
        let shortcut = shortcutRule()
        var matcher = TriggerMatcher()
        _ = matcher.process(KeyboardEvent(kind: .modifierDown, keyCode: 58, modifiers: .option), rules: [tap])
        _ = matcher.process(KeyboardEvent(kind: .reset), rules: [tap])
        XCTAssertTrue(matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 58), rules: [tap]).isEmpty)
        let press = KeyboardEvent(kind: .keyDown, keyCode: 40, modifiers: [.control, .option])
        XCTAssertEqual(matcher.process(press, rules: [shortcut]), [shortcut])
        matcher.reset()
        XCTAssertEqual(matcher.process(press, rules: [shortcut]), [shortcut])
    }

    func testUnobservedModifierPreventsFalseTap() {
        let rule = tapRule(.leftOption)
        var matcher = TriggerMatcher()
        _ = matcher.process(
            KeyboardEvent(kind: .modifierDown, keyCode: 58, modifiers: [.option, .shift]), rules: [rule])
        XCTAssertTrue(
            matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 58, modifiers: .shift), rules: [rule])
                .isEmpty)
    }

    func testUnobservedKeyReleaseCancelsTap() {
        let rule = tapRule(.leftOption)
        var matcher = TriggerMatcher()
        _ = matcher.process(
            KeyboardEvent(kind: .modifierDown, keyCode: 58, modifiers: .option), rules: [rule])
        _ = matcher.process(KeyboardEvent(kind: .keyUp, keyCode: 40), rules: [rule])
        XCTAssertTrue(matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 58), rules: [rule]).isEmpty)
    }

    func testUnsupportedModifierActivityCancelsTap() {
        let rule = tapRule(.leftOption)
        var matcher = TriggerMatcher()
        _ = matcher.process(
            KeyboardEvent(kind: .modifierDown, keyCode: 58, modifiers: .option), rules: [rule])
        _ = matcher.process(KeyboardEvent(kind: .modifierDown, keyCode: 57), rules: [rule])
        XCTAssertTrue(matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 58), rules: [rule]).isEmpty)
    }

    func testSubsequentCleanTapWorksAfterCanceledTap() {
        let rule = tapRule(.leftOption)
        var matcher = TriggerMatcher()
        _ = matcher.process(
            KeyboardEvent(kind: .modifierDown, keyCode: 58, modifiers: .option), rules: [rule])
        _ = matcher.process(KeyboardEvent(kind: .mouseActivity), rules: [rule])
        _ = matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 58), rules: [rule])
        _ = matcher.process(
            KeyboardEvent(kind: .modifierDown, keyCode: 58, modifiers: .option), rules: [rule])
        XCTAssertEqual(matcher.process(KeyboardEvent(kind: .modifierUp, keyCode: 58), rules: [rule]), [rule])
    }
}
