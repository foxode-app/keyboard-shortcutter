import AppKit
import CoreGraphics
import IOKit.hidsystem

#if canImport(ShortcutCore)
import ShortcutCore
#endif

/// Emits the same auxiliary-control event pair as a media key. Tests inject a
/// posting closure to inspect the events without changing the Mac's settings.
@MainActor
final class SystemActionSender {
    private let permissionGranted: @MainActor () -> Bool
    private let makeEvent: @MainActor (SystemAction, Bool) -> CGEvent?
    private let postEvent: @MainActor (CGEvent) -> Void

    init(
        permissionGranted: @escaping @MainActor () -> Bool = {
            ActionExecutor.accessibilityPermissionGranted
        },
        makeEvent: @escaping @MainActor (SystemAction, Bool) -> CGEvent? = SystemActionSender.makeEvent,
        postEvent: @escaping @MainActor (CGEvent) -> Void = { $0.post(tap: .cghidEventTap) }
    ) {
        self.permissionGranted = permissionGranted
        self.makeEvent = makeEvent
        self.postEvent = postEvent
    }

    func send(_ action: SystemAction) throws {
        guard permissionGranted() else {
            throw Failure(
                "System controls require Accessibility permission. Grant it explicitly in Settings, then retry."
            )
        }
        // Allocate both transitions first, so allocation failure cannot leave a media key down.
        guard let down = makeEvent(action, true), let up = makeEvent(action, false) else {
            throw Failure("macOS could not create the system-control key events.")
        }
        guard permissionGranted() else {
            throw Failure(
                "macOS denied permission to send the system control. Check Accessibility permission.")
        }
        postEvent(down)
        postEvent(up)
    }

    static func makeEvent(_ action: SystemAction, isDown: Bool) -> CGEvent? {
        let state = isDown ? Int(NX_KEYDOWN) : Int(NX_KEYUP)
        // IOKit's public NX auxiliary-control format: key type in the upper word,
        // key state in the next byte, and a zero repeat byte (each call is one press).
        guard
            let event = NSEvent.otherEvent(
                with: .systemDefined, location: .zero,
                modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(state << 8)),
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                subtype: Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS),
                data1: (keyType(for: action) << 16) | (state << 8), data2: -1
            )?.cgEvent
        else { return nil }
        event.setIntegerValueField(.eventSourceUserData, value: shortcutterSyntheticEventTag)
        return event
    }

    private static func keyType(for action: SystemAction) -> Int {
        switch action {
        case .volumeDown: Int(NX_KEYTYPE_SOUND_DOWN)
        case .volumeUp: Int(NX_KEYTYPE_SOUND_UP)
        case .mute: Int(NX_KEYTYPE_MUTE)
        case .playPause: Int(NX_KEYTYPE_PLAY)
        case .nextTrack: Int(NX_KEYTYPE_NEXT)
        case .previousTrack: Int(NX_KEYTYPE_PREVIOUS)
        case .brightnessDown: Int(NX_KEYTYPE_BRIGHTNESS_DOWN)
        case .brightnessUp: Int(NX_KEYTYPE_BRIGHTNESS_UP)
        }
    }

    private struct Failure: LocalizedError {
        let message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
