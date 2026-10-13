import Foundation
import XCTest

@testable import ShortcutCore

final class ConfigurationStoreTests: XCTestCase {
    private var directory: URL!
    private var store: ConfigurationStore!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString, isDirectory: true)
        store = ConfigurationStore(url: directory.appendingPathComponent("nested/rules.json"))
    }

    override func tearDownWithError() throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    private func writeRaw(_ data: Data) throws {
        try FileManager.default.createDirectory(
            at: store.url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: store.url)
    }

    func testMissingFileReturnsNil() throws {
        XCTAssertNil(try store.load())
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.url.path))
    }

    func testConfigurationRoundTripsEveryActionAndTrigger() throws {
        let configuration = RulesConfiguration(rules: [
            ShortcutRule(
                name: "Japanese", trigger: .modifierTap(.leftOption),
                action: ShortcutAction(kind: "inputSource", inputSourceID: "installed.japanese")),
            ShortcutRule(
                name: "App", trigger: .modifierTap(.rightCommand),
                action: ShortcutAction(
                    kind: "launchApplication", applicationPath: "/Applications/Example.app"), isEnabled: false
            ),
            ShortcutRule(
                name: "URL",
                trigger: .keyboardShortcut(KeyCombination(keyCode: 49, modifiers: [.command, .shift])),
                action: ShortcutAction(kind: "openURL", url: "https://example.com")),
            ShortcutRule(
                name: "Send", trigger: .modifierTap(.rightControl),
                action: ShortcutAction(
                    kind: "sendShortcut", shortcut: KeyCombination(keyCode: 8, modifiers: .command))),
        ])
        try store.save(configuration)
        XCTAssertEqual(try store.load(), configuration)
        let json = try String(contentsOf: store.url, encoding: .utf8)
        XCTAssertTrue(json.contains("\"schemaVersion\" : 1"))
    }

    func testSavingEditedConfigurationPreservesIdentityAndDisabledState() throws {
        var configuration = ConfigurationStore.defaultConfiguration(
            japaneseSourceID: "ja", englishSourceID: "en")
        try store.save(configuration)
        configuration.rules[0].name = "Custom English mapping"
        configuration.rules[0].isEnabled = false
        configuration.rules.removeLast()
        try store.save(configuration)
        XCTAssertEqual(try store.load(), configuration)
        XCTAssertEqual(try store.load()?.rules.count, 1)
    }

    func testDeletedDefaultsAreNotRecreatedOnLoad() throws {
        try store.save(RulesConfiguration(rules: []))
        XCTAssertEqual(try store.load()?.rules, [])
    }

    func testOlderConfigurationDefaultsToPassiveMonitoringWithoutRewritingFile() throws {
        let ruleID = UUID(uuidString: "D69B713D-C494-4F95-A2A1-D0B9CA3C5B3D")!
        let original = Data(
            """
            {
              "schemaVersion": 1,
              "rules": [{
                "id": "\(ruleID.uuidString)",
                "name": "My existing mapping",
                "trigger": { "kind": "modifierTap", "modifier": "rightOption" },
                "action": { "kind": "inputSource", "inputSourceID": "custom.japanese" },
                "isEnabled": false
              }]
            }
            """.utf8)
        try writeRaw(original)

        let configuration = try XCTUnwrap(store.load())
        XCTAssertFalse(configuration.disableOptionModifiers)
        XCTAssertEqual(configuration.schemaVersion, 1)
        XCTAssertEqual(
            configuration.rules,
            [
                ShortcutRule(
                    id: ruleID, name: "My existing mapping", trigger: .modifierTap(.rightOption),
                    action: ShortcutAction(kind: "inputSource", inputSourceID: "custom.japanese"),
                    isEnabled: false)
            ])
        XCTAssertEqual(try Data(contentsOf: store.url), original)
    }

    func testDisabledOptionModifiersRoundTripsWithVersionOneSchema() throws {
        let configuration = RulesConfiguration(rules: [], disableOptionModifiers: true)
        try store.save(configuration)

        let loaded = try XCTUnwrap(store.load())
        XCTAssertTrue(loaded.disableOptionModifiers)
        XCTAssertEqual(loaded.schemaVersion, 1)
        XCTAssertEqual(loaded, configuration)
    }

    func testTogglingOptionModifiersPreservesExistingRules() throws {
        var configuration = ConfigurationStore.defaultConfiguration(
            japaneseSourceID: "custom.japanese", englishSourceID: "custom.english")
        configuration.rules[0].name = "Custom mapping"
        configuration.rules[0].isEnabled = false
        configuration.rules[1].action = ShortcutAction(kind: "openURL", url: "https://example.com")
        let originalRules = configuration.rules

        for shouldDisable in [true, false] {
            configuration.disableOptionModifiers = shouldDisable
            try store.save(configuration)
            configuration = try XCTUnwrap(store.load())
            XCTAssertEqual(configuration.disableOptionModifiers, shouldDisable)
            XCTAssertEqual(configuration.rules, originalRules)
        }
    }

    func testDefaultsMapLeftOptionToEnglishAndRightOptionToHiragana() {
        let configuration = ConfigurationStore.defaultConfiguration(
            japaneseSourceID: "custom.ja", englishSourceID: "custom.en")
        XCTAssertEqual(
            configuration.rules.map(\.trigger), [.modifierTap(.leftOption), .modifierTap(.rightOption)])
        XCTAssertEqual(configuration.rules.map(\.action.inputSourceID), ["custom.en", "custom.ja"])
        XCTAssertEqual(configuration.rules.map(\.name), ["ABC English input", "Hiragana input"])
        XCTAssertEqual(Set(configuration.rules.map(\.id)).count, 2)
        XCTAssertFalse(configuration.disableOptionModifiers)
    }

    func testMissingDefaultSourcesRemainUnconfigured() {
        let configuration = ConfigurationStore.defaultConfiguration(
            japaneseSourceID: nil, englishSourceID: nil)
        XCTAssertTrue(configuration.rules.allSatisfy { $0.action.inputSourceID == nil })
    }

    func testCorruptFileIsRejectedAndPreserved() throws {
        let original = Data("{ definitely not JSON".utf8)
        try writeRaw(original)
        XCTAssertThrowsError(try store.load())
        XCTAssertEqual(try Data(contentsOf: store.url), original)
    }

    func testFutureVersionIsRejectedBeforeDecodingItsSchema() throws {
        let original = Data("{\"schemaVersion\":42,\"newSchema\":true}".utf8)
        try writeRaw(original)
        XCTAssertThrowsError(try store.load()) { error in
            XCTAssertEqual(error as? ConfigurationError, .unsupportedVersion(42))
        }
        XCTAssertEqual(try Data(contentsOf: store.url), original)
    }

    func testUnsupportedVersionSaveDoesNotReplaceExistingSettings() throws {
        let valid = RulesConfiguration(rules: [])
        try store.save(valid)
        let original = try Data(contentsOf: store.url)
        XCTAssertThrowsError(try store.save(RulesConfiguration(schemaVersion: 2, rules: [])))
        XCTAssertEqual(try Data(contentsOf: store.url), original)
    }

    func testDuplicateRuleIdentifiersAreRejectedOnSaveAndLoad() throws {
        let rule = ConfigurationStore.defaultConfiguration(japaneseSourceID: "ja", englishSourceID: "en")
            .rules[0]
        let invalid = RulesConfiguration(rules: [rule, rule])
        XCTAssertThrowsError(try store.save(invalid)) { error in
            XCTAssertEqual(error as? ConfigurationError, .duplicateRuleID(rule.id))
        }
        try writeRaw(JSONEncoder().encode(invalid))
        XCTAssertThrowsError(try store.load())
    }

    func testInvalidShortcutTriggerIsRejected() {
        let rule = ShortcutRule(
            name: "Invalid", trigger: .keyboardShortcut(KeyCombination(keyCode: 65535)),
            action: ShortcutAction(kind: "openURL"))
        XCTAssertThrowsError(try store.save(RulesConfiguration(rules: [rule]))) { error in
            XCTAssertEqual(error as? ConfigurationError, .invalidTrigger(rule.id))
        }
    }

    func testUnknownActionSurvivesLoadingAndSavingForUserCorrection() throws {
        let rule = ShortcutRule(
            name: "Future action", trigger: .modifierTap(.leftOption),
            action: ShortcutAction(kind: "futureAction"))
        let configuration = RulesConfiguration(rules: [rule])
        try store.save(configuration)
        let loaded = try XCTUnwrap(store.load())
        XCTAssertEqual(loaded, configuration)
        XCTAssertNotNil(RuleActionValidator.validate(loaded.rules[0].action, availableInputSourceIDs: []))
    }
}
