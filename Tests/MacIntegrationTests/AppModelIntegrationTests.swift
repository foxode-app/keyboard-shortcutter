import Foundation
import ShortcutCore
import XCTest

@testable import KeyboardShortcutter

final class AppModelIntegrationTests: XCTestCase {
    private func configurationURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeyboardShortcutterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: directory) }
        return directory.appendingPathComponent("settings.json")
    }

    private func exampleRule() -> ShortcutRule {
        ShortcutRule(
            name: "Example URL",
            trigger: .keyboardShortcut(KeyCombination(keyCode: 40, modifiers: [.control, .option])),
            action: ShortcutAction(kind: "openURL", url: "https://example.com")
        )
    }

    @MainActor
    func testFirstLoadCreatesDefaultsUsingAvailableSources() async throws {
        let url = try configurationURL()
        let model = AppModel(configurationURL: url)
        model.refreshSystemState()
        model.loadConfiguration()

        XCTAssertTrue(model.configurationAvailable)
        XCTAssertTrue(model.isFirstLaunch)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isMonitoring)
        XCTAssertEqual(model.rules.map(\.trigger), [.modifierTap(.leftOption), .modifierTap(.rightOption)])
        let sourceIDs = Set(model.sources.map(\.id))
        for rule in model.rules {
            if let identifier = rule.action.inputSourceID { XCTAssertTrue(sourceIDs.contains(identifier)) }
        }
        let englishRule = try XCTUnwrap(model.rules.first { $0.trigger == .modifierTap(.leftOption) })
        let hiraganaRule = try XCTUnwrap(model.rules.first { $0.trigger == .modifierTap(.rightOption) })
        if let abc = model.sources.first(where: { $0.name.caseInsensitiveCompare("ABC") == .orderedSame }) {
            XCTAssertEqual(englishRule.action.inputSourceID, abc.id)
        } else if let identifier = englishRule.action.inputSourceID {
            let source = try XCTUnwrap(model.sources.first { $0.id == identifier })
            XCTAssertTrue(source.languages.contains { $0.hasPrefix("en") })
        }
        if let identifier = hiraganaRule.action.inputSourceID {
            let source = try XCTUnwrap(model.sources.first { $0.id == identifier })
            XCTAssertTrue(source.languages.contains { $0.hasPrefix("ja") })
        }
        let hiraganaSources = model.sources.filter {
            $0.languages.contains { $0.hasPrefix("ja") }
                && ($0.name.contains("ひらがな") || $0.name.localizedCaseInsensitiveContains("Hiragana"))
        }
        if !hiraganaSources.isEmpty {
            XCTAssertTrue(hiraganaSources.contains { $0.id == hiraganaRule.action.inputSourceID })
        } else {
            XCTAssertNil(hiraganaRule.action.inputSourceID)
        }
        XCTAssertEqual(try ConfigurationStore(url: url).load()?.rules, model.rules)
    }

    @MainActor
    func testDeletingBothDefaultsPersistsAcrossModelReload() async throws {
        let url = try configurationURL()
        let original = AppModel(configurationURL: url)
        original.loadConfiguration()
        for rule in original.rules { original.deleteRule(rule) }
        XCTAssertTrue(original.rules.isEmpty)

        let reloaded = AppModel(configurationURL: url)
        reloaded.refreshSystemState()
        reloaded.loadConfiguration()
        XCTAssertTrue(reloaded.configurationAvailable)
        XCTAssertFalse(reloaded.isFirstLaunch)
        XCTAssertTrue(reloaded.rules.isEmpty)
        XCTAssertEqual(try ConfigurationStore(url: url).load()?.rules, [])
    }

    @MainActor
    func testEditingRulePreservesItsIdentityAndPersistsFields() async throws {
        let url = try configurationURL()
        let original = AppModel(configurationURL: url)
        original.loadConfiguration()
        var edited = try XCTUnwrap(original.rules.first)
        let originalID = edited.id
        edited.name = "Custom mapping"
        edited.isEnabled = false
        edited.trigger = .modifierTap(.rightCommand)
        edited.action = ShortcutAction(kind: "openURL", url: "https://example.com/settings")
        XCTAssertTrue(original.saveRule(edited))
        XCTAssertEqual(original.rules.count, 2)

        let reloaded = AppModel(configurationURL: url)
        reloaded.loadConfiguration()
        XCTAssertEqual(reloaded.rules.first(where: { $0.id == originalID }), edited)
        XCTAssertEqual(reloaded.rules.count, 2)
    }

    @MainActor
    func testAddingTogglingAndDeletingCustomRuleUpdatesStore() async throws {
        let url = try configurationURL()
        try ConfigurationStore(url: url).save(RulesConfiguration(rules: []))
        let model = AppModel(configurationURL: url)
        model.loadConfiguration()
        let added = exampleRule()
        XCTAssertTrue(model.saveRule(added))
        XCTAssertEqual(model.rules, [added])
        model.toggleRule(added)
        XCTAssertFalse(try XCTUnwrap(ConfigurationStore(url: url).load()?.rules.first).isEnabled)
        model.deleteRule(added)
        XCTAssertTrue(model.rules.isEmpty)
        XCTAssertEqual(try ConfigurationStore(url: url).load()?.rules, [])
    }

    @MainActor
    func testCorruptConfigurationBlocksEditsAndPreservesOriginalBytes() async throws {
        let url = try configurationURL()
        let original = Data("{ invalid configuration".utf8)
        try original.write(to: url)
        let model = AppModel(configurationURL: url)
        model.loadConfiguration()

        XCTAssertFalse(model.configurationAvailable)
        XCTAssertFalse(model.isMonitoring)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.saveRule(exampleRule()))
        XCTAssertTrue(model.rules.isEmpty)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    @MainActor
    func testFutureConfigurationBlocksEditsAndPreservesOriginalBytes() async throws {
        let url = try configurationURL()
        let original = Data("{\"schemaVersion\":99,\"futureConfiguration\":{\"preserve\":true}}".utf8)
        try original.write(to: url)
        let model = AppModel(configurationURL: url)
        model.loadConfiguration()

        XCTAssertFalse(model.configurationAvailable)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.saveRule(exampleRule()))
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    @MainActor
    func testLoadingExistingConfigurationDoesNotRewriteFile() async throws {
        let url = try configurationURL()
        let configuration = RulesConfiguration(rules: [exampleRule()])
        // Different whitespace from the store's formatter exposes unintended rewrites.
        let original = try JSONEncoder().encode(configuration)
        try original.write(to: url)
        let model = AppModel(configurationURL: url)
        model.refreshSystemState()
        model.loadConfiguration()

        XCTAssertTrue(model.configurationAvailable)
        XCTAssertFalse(model.isFirstLaunch)
        XCTAssertEqual(model.rules, configuration.rules)
        XCTAssertEqual(try Data(contentsOf: url), original)
    }

    @MainActor
    func testFailedSaveKeepsPreviousInMemoryConfiguration() async throws {
        let url = try configurationURL()
        let model = AppModel(configurationURL: url)
        model.loadConfiguration()
        let originalRules = model.rules
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

        XCTAssertFalse(model.saveRule(exampleRule()))
        XCTAssertEqual(model.rules, originalRules)
        XCTAssertNotNil(model.errorMessage)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
    }

    @MainActor
    func testConflictWarningsFollowEnabledRuleState() async throws {
        let url = try configurationURL()
        try ConfigurationStore(url: url).save(RulesConfiguration(rules: []))
        let model = AppModel(configurationURL: url)
        model.loadConfiguration()
        let first = exampleRule()
        let second = exampleRule()
        XCTAssertTrue(model.saveRule(first))
        XCTAssertTrue(model.saveRule(second))
        XCTAssertEqual(model.conflicts.count, 1)
        XCTAssertEqual(Set(model.conflicts[0].ruleIDs), Set([first.id, second.id]))
        model.toggleRule(second)
        XCTAssertTrue(model.conflicts.isEmpty)
    }

    @MainActor
    func testOptionSuppressionSettingPersistsAcrossRuleEditsAndReload() async throws {
        let url = try configurationURL()
        let model = AppModel(configurationURL: url)
        model.loadConfiguration()
        let originalRules = model.rules
        XCTAssertFalse(model.disableOptionModifiers)

        model.setOptionModifierSuppression(true)
        XCTAssertTrue(model.disableOptionModifiers)
        XCTAssertEqual(model.rules, originalRules)
        XCTAssertFalse(model.isMonitoring, "A model that has not started must not create event taps")
        XCTAssertFalse(model.isOptionSuppressionActive)

        let custom = exampleRule()
        XCTAssertTrue(model.saveRule(custom))
        model.toggleRule(custom)
        model.deleteRule(originalRules[0])
        let saved = try XCTUnwrap(ConfigurationStore(url: url).load())
        XCTAssertTrue(saved.disableOptionModifiers)
        XCTAssertEqual(saved.rules, model.rules)

        let reloaded = AppModel(configurationURL: url)
        reloaded.loadConfiguration()
        XCTAssertTrue(reloaded.disableOptionModifiers)
        XCTAssertEqual(reloaded.rules, model.rules)
        reloaded.setOptionModifierSuppression(false)
        XCTAssertFalse(try XCTUnwrap(ConfigurationStore(url: url).load()).disableOptionModifiers)
        XCTAssertEqual(reloaded.rules, model.rules)
    }

    @MainActor
    func testFailedOptionSuppressionSavePreservesPreviousSetting() async throws {
        let url = try configurationURL()
        let model = AppModel(configurationURL: url)
        model.loadConfiguration()
        let originalRules = model.rules
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)

        model.setOptionModifierSuppression(true)
        XCTAssertFalse(model.disableOptionModifiers)
        XCTAssertFalse(model.isMonitoring)
        XCTAssertFalse(model.isOptionSuppressionActive)
        XCTAssertEqual(model.rules, originalRules)
        XCTAssertNotNil(model.errorMessage)
    }

    @MainActor
    func testFunctionMappingsSwitchRequiredMonitoringModeAcrossEditsAndReload() async throws {
        let url = try configurationURL()
        try ConfigurationStore(url: url).save(RulesConfiguration(rules: [exampleRule()]))
        let model = AppModel(configurationURL: url)
        model.loadConfiguration()
        XCTAssertFalse(model.hasFunctionKeyMappings)
        XCTAssertFalse(model.requiresAccessibilityForMonitoring)

        var functionRule = exampleRule()
        functionRule.trigger = .keyboardShortcut(KeyCombination(keyCode: 101, modifiers: .command))
        XCTAssertTrue(model.saveRule(functionRule))
        XCTAssertTrue(model.hasFunctionKeyMappings)
        XCTAssertTrue(model.requiresAccessibilityForMonitoring)
        XCTAssertFalse(
            model.isMonitoring, "Editing a model that has not started must not install an event tap")
        XCTAssertFalse(model.isFunctionKeySuppressionActive)

        let reloaded = AppModel(configurationURL: url)
        reloaded.loadConfiguration()
        XCTAssertTrue(reloaded.hasFunctionKeyMappings)
        reloaded.toggleRule(functionRule)
        XCTAssertFalse(reloaded.hasFunctionKeyMappings)
        XCTAssertFalse(reloaded.requiresAccessibilityForMonitoring)
        reloaded.toggleRule(try XCTUnwrap(reloaded.rules.first { $0.id == functionRule.id }))
        XCTAssertTrue(reloaded.hasFunctionKeyMappings)
        functionRule.trigger = .keyboardShortcut(KeyCombination(keyCode: 40, modifiers: .command))
        XCTAssertTrue(reloaded.saveRule(functionRule))
        XCTAssertFalse(reloaded.hasFunctionKeyMappings)
        XCTAssertFalse(reloaded.requiresAccessibilityForMonitoring)
    }

    @MainActor
    func testOptionAndFunctionModesStayIndependentWhenMappingsAreDeleted() async throws {
        let url = try configurationURL()
        try ConfigurationStore(url: url).save(RulesConfiguration(rules: [], disableOptionModifiers: true))
        let model = AppModel(configurationURL: url)
        model.loadConfiguration()
        var functionRule = exampleRule()
        functionRule.trigger = .keyboardShortcut(KeyCombination(keyCode: 109))
        XCTAssertTrue(model.saveRule(functionRule))
        model.deleteRule(functionRule)
        XCTAssertFalse(model.hasFunctionKeyMappings)
        XCTAssertTrue(model.disableOptionModifiers)
        XCTAssertTrue(model.requiresAccessibilityForMonitoring)
        model.setOptionModifierSuppression(false)
        XCTAssertFalse(model.requiresAccessibilityForMonitoring)
        model.isRecording = true
        XCTAssertFalse(model.isMonitoring)
        XCTAssertFalse(model.isFunctionKeySuppressionActive)
        XCTAssertFalse(model.isOptionSuppressionActive)
        model.isRecording = false
        XCTAssertFalse(model.isMonitoring)
    }

    @MainActor
    func testBatchFunctionMappingsPersistTogetherWithoutReplacingOtherRules() async throws {
        let url = try configurationURL()
        let original = exampleRule()
        try ConfigurationStore(url: url).save(
            RulesConfiguration(rules: [original], disableOptionModifiers: true))
        let model = AppModel(configurationURL: url)
        model.loadConfiguration()
        let pair = [UInt16(101), 109].map { code in
            ShortcutRule(
                name: "Function \(code)", trigger: .keyboardShortcut(KeyCombination(keyCode: code)),
                action: original.action)
        }
        XCTAssertTrue(model.saveRules(pair))
        let saved = try XCTUnwrap(ConfigurationStore(url: url).load())
        XCTAssertEqual(saved.rules, [original] + pair)
        XCTAssertTrue(saved.disableOptionModifiers)
        XCTAssertTrue(model.hasFunctionKeyMappings)
        XCTAssertFalse(model.isMonitoring)
    }

    @MainActor
    func testFailedBatchSavePreservesRulesAndMonitoringMode() async throws {
        let url = try configurationURL()
        let original = exampleRule()
        try ConfigurationStore(url: url).save(RulesConfiguration(rules: [original]))
        let model = AppModel(configurationURL: url)
        model.loadConfiguration()
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let pair = [UInt16(101), 109].map { code in
            ShortcutRule(
                name: "Function \(code)", trigger: .keyboardShortcut(KeyCombination(keyCode: code)),
                action: original.action)
        }
        XCTAssertFalse(model.saveRules(pair))
        XCTAssertEqual(model.rules, [original])
        XCTAssertFalse(model.hasFunctionKeyMappings)
        XCTAssertFalse(model.requiresAccessibilityForMonitoring)
        XCTAssertFalse(model.isMonitoring)
    }
}
