import Foundation
import XCTest

@testable import KeyboardShortcutter

final class PreferencesMigrationTests: XCTestCase {
    private func domains() -> (UserDefaults, String, String) {
        let current = "KeyboardShortcutterTests.current.\(UUID().uuidString)"
        let legacy = "KeyboardShortcutterTests.legacy.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: current)!
        addTeardownBlock {
            defaults.removePersistentDomain(forName: current)
            defaults.removePersistentDomain(forName: legacy)
        }
        return (defaults, legacy, current)
    }

    func testMigratesPausedStateWithoutCopyingUnrelatedKeysOrDeletingLegacy() {
        let (defaults, legacy, current) = domains()
        defaults.setPersistentDomain(["monitoringPaused": true, "unrelated": "old"], forName: legacy)
        defaults.setPersistentDomain(["currentOnly": "keep"], forName: current)

        PreferencesMigration.migratePausePreference(
            defaults: defaults, legacyDomain: legacy, currentDomain: current)

        XCTAssertTrue(defaults.bool(forKey: "monitoringPaused"))
        XCTAssertEqual(defaults.string(forKey: "currentOnly"), "keep")
        XCTAssertNil(defaults.object(forKey: "unrelated"))
        XCTAssertEqual(defaults.persistentDomain(forName: legacy)?["monitoringPaused"] as? Bool, true)
    }

    func testExistingFalsePreferenceWinsAndMigrationDoesNotRepeat() {
        let (defaults, legacy, current) = domains()
        defaults.setPersistentDomain(["monitoringPaused": true], forName: legacy)
        defaults.setPersistentDomain(["monitoringPaused": false], forName: current)

        PreferencesMigration.migratePausePreference(
            defaults: defaults, legacyDomain: legacy, currentDomain: current)
        PreferencesMigration.migratePausePreference(
            defaults: defaults, legacyDomain: legacy, currentDomain: current)

        XCTAssertEqual(defaults.object(forKey: "monitoringPaused") as? Bool, false)
    }

    func testMissingOrInvalidLegacyPreferenceLeavesCurrentDomainUntouched() {
        let (defaults, legacy, current) = domains()
        PreferencesMigration.migratePausePreference(
            defaults: defaults, legacyDomain: legacy, currentDomain: current)
        XCTAssertNil(defaults.object(forKey: "monitoringPaused"))

        defaults.setPersistentDomain(["monitoringPaused": "invalid"], forName: legacy)
        PreferencesMigration.migratePausePreference(
            defaults: defaults, legacyDomain: legacy, currentDomain: current)
        XCTAssertNil(defaults.object(forKey: "monitoringPaused"))
    }
}
