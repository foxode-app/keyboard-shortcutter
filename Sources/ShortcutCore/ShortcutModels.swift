import Foundation

public enum PhysicalModifier: String, Codable, CaseIterable, Identifiable, Sendable {
    case leftOption, rightOption, leftCommand, rightCommand
    case leftControl, rightControl, leftShift, rightShift

    public var id: String { rawValue }

    public var keyCode: UInt16 {
        switch self {
        case .leftCommand: 55
        case .rightCommand: 54
        case .leftShift: 56
        case .rightShift: 60
        case .leftOption: 58
        case .rightOption: 61
        case .leftControl: 59
        case .rightControl: 62
        }
    }

    public init?(keyCode: UInt16) {
        guard let value = Self.allCases.first(where: { $0.keyCode == keyCode }) else { return nil }
        self = value
    }

    public var title: String {
        switch self {
        case .leftOption: "Left Option"
        case .rightOption: "Right Option"
        case .leftCommand: "Left Command"
        case .rightCommand: "Right Command"
        case .leftControl: "Left Control"
        case .rightControl: "Right Control"
        case .leftShift: "Left Shift"
        case .rightShift: "Right Shift"
        }
    }

    public var logicalModifier: KeyModifiers {
        switch self {
        case .leftOption, .rightOption: .option
        case .leftCommand, .rightCommand: .command
        case .leftControl, .rightControl: .control
        case .leftShift, .rightShift: .shift
        }
    }

    // Caps Lock reports a latched state, not reliable physical down/up transitions.
    // It is deliberately excluded until a release can be observed without a driver.
}

public struct KeyModifiers: OptionSet, Codable, Hashable, Sendable {
    public let rawValue: UInt64

    public init(rawValue: UInt64) { self.rawValue = rawValue }

    public static let shift = Self(rawValue: 1 << 0)
    public static let control = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
    public static let function = Self(rawValue: 1 << 4)
    public static let supported: Self = [.shift, .control, .option, .command, .function]

    public var title: String {
        var symbols: [String] = []
        if contains(.control) { symbols.append("⌃") }
        if contains(.option) { symbols.append("⌥") }
        if contains(.shift) { symbols.append("⇧") }
        if contains(.command) { symbols.append("⌘") }
        if contains(.function) { symbols.append("fn") }
        return symbols.joined()
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(UInt64.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct KeyCombination: Codable, Hashable, Sendable {
    public var keyCode: UInt16
    public var modifiers: KeyModifiers

    public init(keyCode: UInt16, modifiers: KeyModifiers = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    public var title: String { modifiers.title + KeyNames.name(for: keyCode) }

    public var isValid: Bool {
        KeyNames.availableKeys.contains(keyCode) && modifiers.subtracting(.supported).isEmpty
    }
}

public enum ShortcutTrigger: Codable, Hashable, Sendable {
    case modifierTap(PhysicalModifier)
    case keyboardShortcut(KeyCombination)

    public var title: String {
        switch self {
        case .modifierTap(let modifier): "\(modifier.title) alone"
        case .keyboardShortcut(let combination): combination.title
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, modifier, combination }
    private enum Kind: String, Codable { case modifierTap, keyboardShortcut }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .modifierTap:
            self = .modifierTap(try container.decode(PhysicalModifier.self, forKey: .modifier))
        case .keyboardShortcut:
            self = .keyboardShortcut(try container.decode(KeyCombination.self, forKey: .combination))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .modifierTap(let modifier):
            try container.encode(Kind.modifierTap, forKey: .kind)
            try container.encode(modifier, forKey: .modifier)
        case .keyboardShortcut(let combination):
            try container.encode(Kind.keyboardShortcut, forKey: .kind)
            try container.encode(combination, forKey: .combination)
        }
    }
}

public enum SystemAction: String, CaseIterable, Identifiable, Sendable {
    case volumeDown, volumeUp, mute, playPause, nextTrack, previousTrack
    case brightnessDown, brightnessUp

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .volumeDown: "音量を下げる"
        case .volumeUp: "音量を上げる"
        case .mute: "消音の切り替え"
        case .playPause: "再生／一時停止"
        case .nextTrack: "次の曲"
        case .previousTrack: "前の曲"
        case .brightnessDown: "画面を暗くする"
        case .brightnessUp: "画面を明るくする"
        }
    }

    public var repeatsWhileHeld: Bool {
        switch self {
        case .volumeDown, .volumeUp, .brightnessDown, .brightnessUp: true
        case .mute, .playPause, .nextTrack, .previousTrack: false
        }
    }
}

public struct ShortcutAction: Codable, Equatable, Sendable {
    // A string discriminator preserves unknown future actions when loading/saving.
    public var kind: String
    public var inputSourceID: String?
    public var applicationPath: String?
    public var url: String?
    public var shortcut: KeyCombination?
    // Keep the raw value so newer system actions survive an older app's save.
    public var systemAction: String?

    public var resolvedSystemAction: SystemAction? {
        systemAction.flatMap(SystemAction.init(rawValue:))
    }

    public init(
        kind: String,
        inputSourceID: String? = nil,
        applicationPath: String? = nil,
        url: String? = nil,
        shortcut: KeyCombination? = nil,
        systemAction: String? = nil
    ) {
        self.kind = kind
        self.inputSourceID = inputSourceID
        self.applicationPath = applicationPath
        self.url = url
        self.shortcut = shortcut
        self.systemAction = systemAction
    }

    public var title: String {
        switch kind {
        case "inputSource": "Select input source"
        case "launchApplication": "Launch application"
        case "openURL": "Open URL"
        case "sendShortcut": "Send keyboard shortcut"
        case "systemAction": "System control"
        default: "Unavailable action (\(kind))"
        }
    }
}

public struct ShortcutRule: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var trigger: ShortcutTrigger
    public var action: ShortcutAction
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(), name: String, trigger: ShortcutTrigger,
        action: ShortcutAction, isEnabled: Bool = true
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.action = action
        self.isEnabled = isEnabled
    }
}

public struct RulesConfiguration: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var rules: [ShortcutRule]
    public var disableOptionModifiers: Bool

    public init(
        schemaVersion: Int = 1, rules: [ShortcutRule], disableOptionModifiers: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.rules = rules
        self.disableOptionModifiers = disableOptionModifiers
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, rules, disableOptionModifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        rules = try container.decode([ShortcutRule].self, forKey: .rules)
        // This additive version-1 setting preserves passive monitoring for existing installations.
        disableOptionModifiers =
            try container.decodeIfPresent(Bool.self, forKey: .disableOptionModifiers)
            ?? false
    }
}

public enum FunctionKey {
    /// Physical macOS virtual key codes in F1 through F20 order.
    public static let keyCodes: [UInt16] = [
        122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
        103, 111, 105, 107, 113, 106, 64, 79, 80, 90,
    ]

    public static func contains(_ keyCode: UInt16) -> Bool {
        keyCodes.contains(keyCode)
    }
}

public enum KeyNames {
    // Physical macOS virtual key positions; letters describe the ANSI layout.
    // They are labels, never text read from an event or a user's input stream.
    private static let names: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
        8: "C", 9: "V", 10: "ISO §", 11: "B", 12: "Q", 13: "W", 14: "E",
        15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4",
        22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "−", 28: "8",
        29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P",
        36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
        43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
        50: "`", 51: "Delete", 53: "Escape", 64: "F17", 65: "Keypad .",
        67: "Keypad *", 69: "Keypad +", 71: "Keypad Clear", 75: "Keypad /",
        76: "Keypad Enter", 78: "Keypad −", 79: "F18", 80: "F19", 81: "Keypad =",
        82: "Keypad 0", 83: "Keypad 1", 84: "Keypad 2", 85: "Keypad 3",
        86: "Keypad 4", 87: "Keypad 5", 88: "Keypad 6", 89: "Keypad 7",
        90: "F20", 91: "Keypad 8", 92: "Keypad 9", 93: "JIS ¥", 94: "JIS _",
        95: "JIS Keypad ,", 96: "F5", 97: "F6", 98: "F7", 99: "F3",
        100: "F8", 101: "F9", 102: "JIS Eisu", 103: "F11", 104: "JIS Kana",
        105: "F13", 106: "F16", 107: "F14", 109: "F10", 111: "F12",
        113: "F15", 114: "Help", 115: "Home", 116: "Page Up", 117: "Forward Delete",
        118: "F4", 119: "End", 120: "F2", 121: "Page Down", 122: "F1",
        123: "←", 124: "→", 125: "↓", 126: "↑",
    ]

    public static let availableKeys: [UInt16] = names.keys.sorted()

    public static func name(for keyCode: UInt16) -> String {
        names[keyCode] ?? PhysicalModifier(keyCode: keyCode)?.title ?? "Key \(keyCode)"
    }
}
