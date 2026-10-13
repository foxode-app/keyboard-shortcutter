import Foundation

public enum ConfigurationError: LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case duplicateRuleID(UUID)
    case invalidTrigger(UUID)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            "Settings version \(version) is not supported. The existing file has been preserved."
        case .duplicateRuleID(let id):
            "Settings contain a duplicate mapping ID (\(id)). The existing file has been preserved."
        case .invalidTrigger(let id):
            "Mapping \(id) has an unsupported keyboard trigger. The existing file has been preserved."
        }
    }
}

public struct ConfigurationStore {
    public let url: URL

    public init(url: URL) { self.url = url }

    public func load() throws -> RulesConfiguration? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        // Inspect the version before decoding the body, since newer schemas may differ.
        struct Version: Decodable { let schemaVersion: Int }
        let version = try JSONDecoder().decode(Version.self, from: data)
        guard version.schemaVersion == 1 else {
            throw ConfigurationError.unsupportedVersion(version.schemaVersion)
        }
        let configuration = try JSONDecoder().decode(RulesConfiguration.self, from: data)
        try validate(configuration)
        return configuration
    }

    public func save(_ configuration: RulesConfiguration) throws {
        try validate(configuration)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(configuration)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private func validate(_ configuration: RulesConfiguration) throws {
        guard configuration.schemaVersion == 1 else {
            throw ConfigurationError.unsupportedVersion(configuration.schemaVersion)
        }
        var identifiers: Set<UUID> = []
        for rule in configuration.rules {
            guard identifiers.insert(rule.id).inserted else {
                throw ConfigurationError.duplicateRuleID(rule.id)
            }
            if case .keyboardShortcut(let combination) = rule.trigger, !combination.isValid {
                throw ConfigurationError.invalidTrigger(rule.id)
            }
        }
    }

    public static func defaultConfiguration(
        japaneseSourceID: String?, englishSourceID: String?
    ) -> RulesConfiguration {
        RulesConfiguration(rules: [
            ShortcutRule(
                name: "ABC English input", trigger: .modifierTap(.leftOption),
                action: ShortcutAction(kind: "inputSource", inputSourceID: englishSourceID)
            ),
            ShortcutRule(
                name: "Hiragana input", trigger: .modifierTap(.rightOption),
                action: ShortcutAction(kind: "inputSource", inputSourceID: japaneseSourceID)
            ),
        ])
    }
}
