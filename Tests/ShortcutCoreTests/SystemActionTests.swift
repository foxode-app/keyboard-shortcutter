import Foundation
import XCTest

@testable import ShortcutCore

final class SystemActionTests: XCTestCase {
    func testAllFunctionKeysHaveValidDistinctPhysicalCodesAndOrderedNames() {
        XCTAssertEqual(FunctionKey.keyCodes.count, 20)
        XCTAssertEqual(Set(FunctionKey.keyCodes).count, 20)
        for (index, code) in FunctionKey.keyCodes.enumerated() {
            XCTAssertTrue(FunctionKey.contains(code))
            XCTAssertTrue(KeyCombination(keyCode: code).isValid)
            XCTAssertEqual(KeyNames.name(for: code), "F\(index + 1)")
        }
        for code: UInt16 in [0, 40, 63, 123, 65535] {
            XCTAssertFalse(FunctionKey.contains(code))
        }
    }

    func testSystemControlsValidateAndRoundTripWithVersionOneConfiguration() throws {
        let rules = SystemAction.allCases.map { control in
            ShortcutRule(
                name: control.title, trigger: .keyboardShortcut(KeyCombination(keyCode: 101)),
                action: ShortcutAction(kind: "systemAction", systemAction: control.rawValue))
        }
        let configuration = RulesConfiguration(rules: rules)
        let decoded = try JSONDecoder().decode(
            RulesConfiguration.self, from: JSONEncoder().encode(configuration))
        XCTAssertEqual(decoded, configuration)
        XCTAssertEqual(decoded.schemaVersion, 1)
        for rule in decoded.rules {
            XCTAssertNotNil(rule.action.resolvedSystemAction)
            XCTAssertNil(RuleActionValidator.validate(rule.action, availableInputSourceIDs: []))
        }
    }

    func testAbsentAndUnknownSystemControlsAreInvalidButPreserved() throws {
        for value in [nil, "", "futureSystemControl"] as [String?] {
            let action = ShortcutAction(kind: "systemAction", systemAction: value)
            let decoded = try JSONDecoder().decode(ShortcutAction.self, from: JSONEncoder().encode(action))
            XCTAssertEqual(decoded, action)
            XCTAssertNil(decoded.resolvedSystemAction)
            XCTAssertNotNil(RuleActionValidator.validate(decoded, availableInputSourceIDs: []))
        }
    }

    func testExistingActionWithoutSystemControlKeepsItsSettings() throws {
        let oldJSON = Data(
            #"{"kind":"sendShortcut","shortcut":{"keyCode":101,"modifiers":16}}"#.utf8)
        let decoded = try JSONDecoder().decode(ShortcutAction.self, from: oldJSON)
        XCTAssertEqual(decoded.kind, "sendShortcut")
        XCTAssertNil(decoded.systemAction)
        XCTAssertEqual(decoded.shortcut, KeyCombination(keyCode: 101, modifiers: .function))
        XCTAssertNil(RuleActionValidator.validate(decoded, availableInputSourceIDs: []))
    }
}
