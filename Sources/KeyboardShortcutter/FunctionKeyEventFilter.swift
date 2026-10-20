import CoreGraphics

#if canImport(ShortcutCore)
import ShortcutCore
#endif

/// Owns complete physical F-key presses only after the matcher accepts a mapping.
/// An unmatched down must retain its corresponding repeats and release, even if
/// the modifier flags or enabled mappings change while the key is held.
struct FunctionKeyEventFilter {
    private var consumedKeys: Set<UInt16> = []

    mutating func reset() { consumedKeys.removeAll(keepingCapacity: true) }

    /// A fresh physical press after idle reconciliation cannot belong to the lost release.
    mutating func releaseOwnership(of keyCode: UInt16) { consumedKeys.remove(keyCode) }

    mutating func shouldConsume(
        _ event: CGEvent, type: CGEventType, enabled: Bool, matched: Bool
    ) -> Bool {
        guard enabled,
            event.getIntegerValueField(.eventSourceUserData) != shortcutterSyntheticEventTag,
            type == .keyDown || type == .keyUp
        else { return false }
        let keyCode = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
        guard FunctionKey.contains(keyCode) else { return false }
        if type == .keyUp { return consumedKeys.remove(keyCode) != nil }
        if consumedKeys.contains(keyCode) { return true }
        guard matched, event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return false }
        consumedKeys.insert(keyCode)
        return true
    }
}
