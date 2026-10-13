import XCTest

@testable import ShortcutCore

final class RuleActionValidatorTests: XCTestCase {
    func testInputSourceMustBeConfiguredAndAvailable() {
        XCTAssertNotNil(
            RuleActionValidator.validate(
                ShortcutAction(kind: "inputSource"), availableInputSourceIDs: ["available"]))
        XCTAssertNotNil(
            RuleActionValidator.validate(
                ShortcutAction(kind: "inputSource", inputSourceID: "missing"),
                availableInputSourceIDs: ["available"]))
        XCTAssertNil(
            RuleActionValidator.validate(
                ShortcutAction(kind: "inputSource", inputSourceID: "available"),
                availableInputSourceIDs: ["available"]))
    }

    func testApplicationMustBeAnExistingAbsoluteAppPath() {
        XCTAssertNil(
            RuleActionValidator.validate(
                ShortcutAction(kind: "launchApplication", applicationPath: "/Applications/Example.app"),
                availableInputSourceIDs: [], applicationExists: { _ in true }))
        for path in [nil, "Example.app", "/Applications/Example.txt"] as [String?] {
            XCTAssertNotNil(
                RuleActionValidator.validate(
                    ShortcutAction(kind: "launchApplication", applicationPath: path),
                    availableInputSourceIDs: [], applicationExists: { _ in true }))
        }
        XCTAssertNotNil(
            RuleActionValidator.validate(
                ShortcutAction(kind: "launchApplication", applicationPath: "/Applications/Missing.app"),
                availableInputSourceIDs: [], applicationExists: { _ in false }))
    }

    func testValidURLsAreAccepted() {
        for url in [
            "https://example.com", "http://localhost:8080/path?q=value", "mailto:person@example.com",
            "HTTPS://EXAMPLE.COM",
        ] {
            XCTAssertNil(
                RuleActionValidator.validate(
                    ShortcutAction(kind: "openURL", url: url), availableInputSourceIDs: []), url)
        }
    }

    func testInvalidOrUnsupportedURLsAreRejected() {
        for url in [
            nil, "", "example.com", "https:", "mailto:", "file:///tmp/test", "javascript:alert(1)",
            "custom-app://open",
        ] as [String?] {
            XCTAssertNotNil(
                RuleActionValidator.validate(
                    ShortcutAction(kind: "openURL", url: url), availableInputSourceIDs: []), url ?? "nil")
        }
    }

    func testShortcutMustUseKnownNonmodifierKeyAndKnownModifierFlags() {
        XCTAssertNil(
            RuleActionValidator.validate(
                ShortcutAction(
                    kind: "sendShortcut",
                    shortcut: KeyCombination(keyCode: 40, modifiers: [.control, .option])),
                availableInputSourceIDs: []))
        XCTAssertNotNil(
            RuleActionValidator.validate(ShortcutAction(kind: "sendShortcut"), availableInputSourceIDs: []))
        for code: UInt16 in [55, 56, 57, 58, 59, 60, 61, 62, 63, 65535] {
            XCTAssertNotNil(
                RuleActionValidator.validate(
                    ShortcutAction(kind: "sendShortcut", shortcut: KeyCombination(keyCode: code)),
                    availableInputSourceIDs: []))
        }
        XCTAssertNotNil(
            RuleActionValidator.validate(
                ShortcutAction(
                    kind: "sendShortcut",
                    shortcut: KeyCombination(keyCode: 40, modifiers: KeyModifiers(rawValue: 1 << 63))),
                availableInputSourceIDs: []))
    }

    func testUnknownActionIsReportedWithoutCrash() {
        let action = ShortcutAction(kind: "runArbitraryShellCommand")
        XCTAssertNotNil(RuleActionValidator.validate(action, availableInputSourceIDs: []))
        XCTAssertTrue(action.title.contains("Unavailable"))
    }

    func testKeyLabelsCoverPhysicalKeyboardWithoutReadingTypedContent() {
        XCTAssertEqual(KeyNames.name(for: 40), "K")
        XCTAssertEqual(KeyNames.name(for: 49), "Space")
        XCTAssertEqual(KeyNames.name(for: 65535), "Key 65535")
        XCTAssertEqual(KeyCombination(keyCode: 40, modifiers: [.control, .option]).title, "⌃⌥K")
        XCTAssertTrue(KeyNames.availableKeys.contains(102), "JIS Eisu")
        XCTAssertTrue(KeyNames.availableKeys.contains(104), "JIS Kana")
        XCTAssertFalse(KeyNames.availableKeys.contains(57), "Latched Caps Lock")
    }
}
