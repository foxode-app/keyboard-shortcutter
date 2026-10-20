import AppKit
import Carbon
import CoreGraphics
import os

#if canImport(ShortcutCore)
import ShortcutCore
#endif

/// Finishes a Japanese Kana switch that the focused app did not apply.
///
/// `TISSelectInputSource` from this background app can change the system selection while the
/// focused client leaves its input method inactive, so typing stays ASCII under the "あ" menu.
/// A client that applies the switch answers with further selected-source notifications; a stale
/// client leaves only the one for this app's own selection. Without that answer, the previous
/// ASCII layout is selected again so the client's text-input system owns the next key, and Kana
/// then lets the client switch itself. Kana is never sent while Japanese is selected: an active
/// input method treats it as input, which earlier versions saw as control characters, spaces,
/// history recall, or reconversion of the preceding text.
@MainActor
final class InputMethodActivationRecovery {
    struct Timing {
        /// A focused text field answers within tens of milliseconds when the switch applies.
        var confirmation: TimeInterval = 0.15
        /// Lets the client apply the ASCII layout before Kana arrives.
        var asciiSettle: TimeInterval = 0.08
    }

    private enum Stage { case confirming, recovering }

    private struct Pending {
        let id = UUID()
        let targetID: String
        let asciiID: String
        let targetPID: pid_t?
        let baseline: Int
        var stage = Stage.confirming
    }

    private let service: any InputSourceSelecting
    private let timing: Timing
    private let permissionGranted: @MainActor () -> Bool
    private let physicalModifiers: @MainActor () -> KeyModifiers
    private let frontmostPID: @MainActor () -> pid_t?
    private let secureInputEnabled: @MainActor () -> Bool
    private let postEvent: @MainActor (CGEvent) -> Void
    private let schedule: @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void
    private let logger = Logger(subsystem: "com.foxode.keyboardshortcutter.app", category: "InputSource")
    private var observer: SelectedSourceObserver?
    private var notificationCount = 0
    private var pending: Pending?

    /// The source whose switch is still being confirmed or recovered.
    var pendingTargetID: String? { pending?.targetID }

    init(
        service: any InputSourceSelecting,
        timing: Timing = Timing(),
        observesSystemNotifications: Bool = true,
        permissionGranted: @escaping @MainActor () -> Bool = {
            ActionExecutor.accessibilityPermissionGranted
        },
        physicalModifiers: @escaping @MainActor () -> KeyModifiers = {
            EventMonitor.modifiers(
                from: CGEventSource.flagsState(.hidSystemState),
                physicalFunctionDown: CGEventSource.keyState(.hidSystemState, key: 63))
        },
        frontmostPID: @escaping @MainActor () -> pid_t? = {
            NSWorkspace.shared.frontmostApplication?.processIdentifier
        },
        secureInputEnabled: @escaping @MainActor () -> Bool = { IsSecureEventInputEnabled() },
        postEvent: @escaping @MainActor (CGEvent) -> Void = { $0.post(tap: .cgSessionEventTap) },
        schedule: @escaping @MainActor (TimeInterval, @escaping @MainActor () -> Void) -> Void = {
            delay, work in
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { work() }
        }
    ) {
        self.service = service
        self.timing = timing
        self.permissionGranted = permissionGranted
        self.physicalModifiers = physicalModifiers
        self.frontmostPID = frontmostPID
        self.secureInputEnabled = secureInputEnabled
        self.postEvent = postEvent
        self.schedule = schedule
        if observesSystemNotifications {
            observer = SelectedSourceObserver { [weak self] in self?.selectedSourceDidChange() }
        }
    }

    /// Kana selects Hiragana in Apple's Japanese input method; other sources keep plain TIS behavior.
    static func canRecover(_ source: InputSourceService.Source) -> Bool {
        source.id.hasPrefix("com.apple.inputmethod.Kotoeri.")
            && ["com.apple.inputmethod.Japanese", "com.apple.inputmethod.Japanese.Hiragana"].contains(
                source.inputModeID)
    }

    /// Call right after TIS selected `target` while `previous` was the selected source.
    func watch(_ target: InputSourceService.Source, after previous: InputSourceService.Source?) {
        pending = nil
        guard Self.canRecover(target), let previous, previous.isASCIICapableLayout, previous.id != target.id
        else { return }
        let next = Pending(
            targetID: target.id, asciiID: previous.id, targetPID: frontmostPID(), baseline: notificationCount)
        pending = next
        schedule(timing.confirmation) { [weak self] in self?.confirmationExpired(next.id) }
    }

    func cancel() { pending = nil }

    /// Production code receives these from the distributed notification center.
    func selectedSourceDidChange() {
        notificationCount &+= 1
        // This app's own selection accounts for one notification; another is the client's answer.
        if let pending, pending.stage == .confirming, notificationCount - pending.baseline >= 2 {
            self.pending = nil
        }
    }

    private func confirmationExpired(_ id: UUID) {
        guard var current = pending, current.id == id, current.stage == .confirming else { return }
        if let reason = skipReason(expecting: current.targetID, in: current.targetPID) {
            pending = nil
            logger.notice(
                "Japanese input activation was not confirmed; recovery skipped because \(reason, privacy: .public)."
            )
            return
        }
        do {
            try service.select(id: current.asciiID)
        } catch {
            pending = nil
            logger.error("Japanese input recovery could not reselect the ASCII layout.")
            return
        }
        current.stage = .recovering
        pending = current
        logger.notice("Japanese input activation was not confirmed; retrying through the Kana key.")
        schedule(timing.asciiSettle) { [weak self] in self?.sendKana(id) }
    }

    private func sendKana(_ id: UUID) {
        guard let current = pending, current.id == id, current.stage == .recovering else { return }
        pending = nil
        if let reason = skipReason(expecting: current.asciiID, in: current.targetPID) {
            logger.notice("Kana recovery stopped because \(reason, privacy: .public).")
            return
        }
        guard let events = Self.kanaEvents() else {
            logger.error("Kana recovery could not allocate keyboard events.")
            return
        }
        for event in events { postEvent(event) }
    }

    private func skipReason(expecting sourceID: String, in targetPID: pid_t?) -> String? {
        if service.currentSourceID() != sourceID { return "the selected source changed" }
        if frontmostPID() != targetPID { return "the frontmost app changed" }
        if secureInputEnabled() { return "secure input is active" }
        if !physicalModifiers().isEmpty { return "a modifier is held" }
        if !permissionGranted() { return "Accessibility permission is unavailable" }
        return nil
    }

    private static func kanaEvents() -> [CGEvent]? {
        // A private source leaves hardware key state untouched, and its default keyboard type
        // matches the attached keyboard. Allocate both events before posting either one.
        guard let source = CGEventSource(stateID: .privateState) else { return nil }
        var events: [CGEvent] = []
        for down in [true, false] {
            guard
                let event = CGEvent(
                    keyboardEventSource: source, virtualKey: CGKeyCode(kVK_JIS_Kana), keyDown: down)
            else { return nil }
            event.flags = []
            event.setIntegerValueField(.eventSourceUserData, value: shortcutterSyntheticEventTag)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            events.append(event)
        }
        return events
    }
}

/// Receives TIS selection changes immediately; this app is never active to unsuspend delivery.
private final class SelectedSourceObserver: NSObject {
    private let handler: @MainActor () -> Void

    init(handler: @escaping @MainActor () -> Void) {
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self, selector: #selector(selectedSourceChanged),
            name: Notification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String), object: nil,
            suspensionBehavior: .deliverImmediately)
    }

    deinit { DistributedNotificationCenter.default().removeObserver(self) }

    @objc private func selectedSourceChanged() {
        DispatchQueue.main.async { [handler] in handler() }
    }
}
