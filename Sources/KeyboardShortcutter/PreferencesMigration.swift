import Foundation

enum PreferencesMigration {
    static func migrateLegacyPreferences() {
        let currentDomain = "com.foxode.keyboardshortcutter.app"
        guard Bundle.main.bundleIdentifier == currentDomain else { return }
        migratePausePreference(
            defaults: .standard,
            legacyDomain: "local.keyboardshortcutter.app",
            currentDomain: currentDomain
        )
    }

    /// Only copy the app-owned preference. Rules retain their existing JSON path.
    static func migratePausePreference(
        defaults: UserDefaults, legacyDomain: String, currentDomain: String
    ) {
        let key = "monitoringPaused"
        var current = defaults.persistentDomain(forName: currentDomain) ?? [:]
        guard current[key] == nil,
            let value = defaults.persistentDomain(forName: legacyDomain)?[key] as? Bool
        else { return }
        current[key] = value
        defaults.setPersistentDomain(current, forName: currentDomain)
    }
}
