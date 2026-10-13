import Foundation

public struct KeyboardEvent: Sendable {
    public enum Kind: Sendable {
        case keyDown, keyUp, modifierDown, modifierUp, mouseActivity, reset
    }

    public var kind: Kind
    public var keyCode: UInt16
    public var modifiers: KeyModifiers
    public var isRepeat: Bool

    public init(kind: Kind, keyCode: UInt16 = 0, modifiers: KeyModifiers = [], isRepeat: Bool = false) {
        self.kind = kind
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.isRepeat = isRepeat
    }
}

public struct RuleConflict: Equatable, Sendable {
    public var ruleIDs: [UUID]
    public var message: String

    public init(ruleIDs: [UUID], message: String) {
        self.ruleIDs = ruleIDs
        self.message = message
    }
}

public struct TriggerMatcher: Sendable {
    private var pressedKeys: Set<UInt16> = []
    private var pressedModifiers: Set<UInt16> = []
    private var tapCandidates: Set<UInt16> = []
    private var repeatablePresses: [UInt16: ShortcutRule] = [:]

    public init() {}

    public mutating func reset() {
        pressedKeys.removeAll(keepingCapacity: true)
        pressedModifiers.removeAll(keepingCapacity: true)
        tapCandidates.removeAll(keepingCapacity: true)
        repeatablePresses.removeAll(keepingCapacity: true)
    }

    public mutating func process(_ event: KeyboardEvent, rules: [ShortcutRule]) -> [ShortcutRule] {
        switch event.kind {
        case .reset:
            reset()
        case .mouseActivity:
            tapCandidates.removeAll(keepingCapacity: true)
        case .keyDown:
            tapCandidates.removeAll(keepingCapacity: true)
            let isNewPress = pressedKeys.insert(event.keyCode).inserted
            let combination = KeyCombination(keyCode: event.keyCode, modifiers: event.modifiers)
            guard combination.isValid else { return [] }
            let trigger = ShortcutTrigger.keyboardShortcut(combination)
            if event.isRepeat {
                // Never start an action from a key held before monitoring began. A repeat must
                // still target the same unambiguous action captured on its initial press.
                guard !isNewPress, let initial = repeatablePresses[event.keyCode],
                    initial.trigger == trigger
                else { return [] }
                let matches = matching(trigger, rules: rules)
                guard let current = matches.first, current.id == initial.id,
                    current.action == initial.action
                else { return [] }
                return matches
            }
            guard isNewPress else { return [] }
            let matches = matching(trigger, rules: rules)
            if let rule = matches.first, rule.action.kind == "systemAction",
                rule.action.resolvedSystemAction?.repeatsWhileHeld == true
            {
                repeatablePresses[event.keyCode] = rule
            }
            return matches
        case .keyUp:
            // A key held before monitoring began must still invalidate an active tap.
            tapCandidates.removeAll(keepingCapacity: true)
            pressedKeys.remove(event.keyCode)
            repeatablePresses.removeValue(forKey: event.keyCode)
        case .modifierDown:
            guard let modifier = PhysicalModifier(keyCode: event.keyCode) else {
                tapCandidates.removeAll(keepingCapacity: true)
                return []
            }
            guard !pressedModifiers.contains(event.keyCode) else { return [] }
            let isAlone =
                pressedKeys.isEmpty && pressedModifiers.isEmpty
                && event.modifiers.subtracting(modifier.logicalModifier).isEmpty
            tapCandidates.removeAll(keepingCapacity: true)
            pressedModifiers.insert(event.keyCode)
            if isAlone && !event.isRepeat { tapCandidates.insert(event.keyCode) }
        case .modifierUp:
            guard let modifier = PhysicalModifier(keyCode: event.keyCode) else {
                tapCandidates.removeAll(keepingCapacity: true)
                return []
            }
            let wasPressed = pressedModifiers.remove(event.keyCode) != nil
            let wasCandidate = tapCandidates.remove(event.keyCode) != nil
            // Nonempty flags on release can reveal an unobserved held modifier.
            guard wasPressed, wasCandidate, event.modifiers.isEmpty else { return [] }
            return matching(.modifierTap(modifier), rules: rules)
        }
        return []
    }

    private func matching(_ trigger: ShortcutTrigger, rules: [ShortcutRule]) -> [ShortcutRule] {
        var result: ShortcutRule?
        for rule in rules where rule.isEnabled && rule.trigger == trigger {
            // Ambiguous rules are deliberately suppressed, not resolved by list order.
            guard result == nil else { return [] }
            result = rule
        }
        return result.map { [$0] } ?? []
    }

    public static func conflicts(in rules: [ShortcutRule]) -> [RuleConflict] {
        var seen: Set<ShortcutTrigger> = []
        return rules.filter(\.isEnabled).compactMap { rule in
            guard seen.insert(rule.trigger).inserted else { return nil }
            let duplicates = rules.filter { $0.isEnabled && $0.trigger == rule.trigger }
            guard duplicates.count > 1 else { return nil }
            return RuleConflict(
                ruleIDs: duplicates.map(\.id),
                message:
                    "\(rule.trigger.title) is assigned to \(duplicates.count) enabled mappings. Disable or change duplicates; none will run."
            )
        }
    }
}
