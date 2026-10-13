import Foundation

public enum RuleActionValidator {
    public static func validate(
        _ action: ShortcutAction,
        availableInputSourceIDs: Set<String>,
        applicationExists: (String) -> Bool = { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
                && isDirectory.boolValue
        }
    ) -> String? {
        switch action.kind {
        case "inputSource":
            guard let identifier = action.inputSourceID, !identifier.isEmpty else {
                return "Choose an input source installed on this Mac."
            }
            guard availableInputSourceIDs.contains(identifier) else {
                return "The configured input source is unavailable. Choose another source in Settings."
            }
        case "launchApplication":
            guard let path = action.applicationPath, path.hasPrefix("/"),
                URL(fileURLWithPath: path).pathExtension.lowercased() == "app",
                applicationExists(path)
            else {
                return "Choose an existing macOS application (.app)."
            }
        case "openURL":
            guard let value = action.url, let components = URLComponents(string: value),
                let scheme = components.scheme?.lowercased(),
                ["http", "https", "mailto"].contains(scheme), components.url != nil
            else {
                return "Enter a complete URL using https, http, or mailto."
            }
            if scheme == "mailto" {
                guard !components.path.isEmpty else { return "Enter a mailto recipient." }
            } else if components.host?.isEmpty != false {
                return "Enter a URL with a hostname."
            }
        case "sendShortcut":
            guard let shortcut = action.shortcut, shortcut.isValid else {
                return "Choose a valid key and optional modifiers to send."
            }
        case "systemAction":
            guard action.resolvedSystemAction != nil else {
                return "Choose an available volume, playback, or brightness control."
            }
        default:
            return "This action type is unavailable in this version: \(action.kind)."
        }
        return nil
    }
}
