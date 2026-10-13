import CoreGraphics

/// Transforms only the outgoing event stream. Match triggers against the original event first.
struct OptionEventFilter {
    enum Failure: Error {
        case cannotCreateKeyboardEvent
    }

    // NX_DEVICELALTKEYMASK and NX_DEVICERALTKEYMASK from IOLLEvent.h.
    static let optionMask = CGEventFlags.maskAlternate.rawValue | 0x20 | 0x40

    /// Does not post events, inspect characters, or change hardware key state.
    func apply(to event: CGEvent, type: CGEventType, enabled: Bool) throws -> CGEvent? {
        guard enabled,
            event.getIntegerValueField(.eventSourceUserData) != shortcutterSyntheticEventTag
        else { return event }

        let code = event.getIntegerValueField(.keyboardEventKeycode)
        if type == .flagsChanged && (code == 58 || code == 61) { return nil }

        let flags = CGEventFlags(rawValue: event.flags.rawValue & ~Self.optionMask)
        guard flags != event.flags else { return event }
        if type == .keyDown || type == .keyUp {
            // Flags alone do not clear an already-translated Option character/dead key.
            // A fresh keycode event lets macOS translate the current layout/IME with the
            // cleaned flags. Never read, copy, log, or retain the original Unicode payload.
            guard let source = CGEventSource(stateID: .privateState) else {
                throw Failure.cannotCreateKeyboardEvent
            }
            source.keyboardType = UInt32(clamping: event.getIntegerValueField(.keyboardEventKeyboardType))
            guard
                let replacement = CGEvent(
                    keyboardEventSource: source, virtualKey: UInt16(clamping: code), keyDown: type == .keyDown
                )
            else { throw Failure.cannotCreateKeyboardEvent }
            replacement.flags = flags
            replacement.timestamp = event.timestamp
            replacement.location = event.location
            for field in Self.preservedKeyboardFields {
                replacement.setIntegerValueField(field, value: event.getIntegerValueField(field))
            }
            return replacement
        }
        // Preserve all mouse/scroll payload and non-Option modifier transitions.
        event.flags = flags
        return event
    }

    private static let preservedKeyboardFields: [CGEventField] = [
        .keyboardEventAutorepeat, .keyboardEventKeyboardType,
        .eventTargetProcessSerialNumber, .eventTargetUnixProcessID,
        .eventSourceUnixProcessID, .eventSourceUserData, .eventSourceUserID,
        .eventSourceGroupID, .eventSourceStateID,
    ]
}
