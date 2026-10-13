import AppKit
import ApplicationServices
import CoreGraphics

#if canImport(ShortcutCore)
import ShortcutCore
#endif

@MainActor
final class ActionExecutor {
    private let handlers: [String: any ActionHandler]
    private let shortcutHandler: SendShortcutActionHandler
    private var executionGeneration = 0

    static var accessibilityPermissionGranted: Bool { AXIsProcessTrusted() && CGPreflightPostEventAccess() }

    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    init(inputSourceService: InputSourceService) {
        let sender = SendShortcutActionHandler()
        shortcutHandler = sender
        handlers = [
            "inputSource": InputSourceActionHandler(service: inputSourceService),
            "launchApplication": LaunchApplicationActionHandler(),
            "openURL": OpenURLActionHandler(),
            "sendShortcut": sender,
        ]
    }

    func execute(_ action: ShortcutAction, completion: @escaping (Result<Void, Error>) -> Void) {
        // Workspace, TIS and synthetic-event work must never run inside the event-tap callback.
        let generation = executionGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard generation == self.executionGeneration else {
                completion(
                    .failure(ActionFailure("The action was canceled because monitoring was reset or paused."))
                )
                return
            }
            guard let handler = self.handlers[action.kind] else {
                completion(
                    .failure(
                        ActionFailure("This action type (\(action.kind)) is not supported by this version.")))
                return
            }
            handler.execute(action, completion: completion)
        }
    }

    /// Feed events before matching rules so a shortcut action knows which physical keys remain held.
    func observe(_ event: KeyboardEvent) {
        if event.kind == .reset { executionGeneration &+= 1 }
        shortcutHandler.observe(event)
    }

    func cancelPendingAction() {
        executionGeneration &+= 1
        shortcutHandler.cancelPendingAction()
    }
}

private struct ActionFailure: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

@MainActor
private protocol ActionHandler {
    func execute(_ action: ShortcutAction, completion: @escaping (Result<Void, Error>) -> Void)
}

@MainActor
private final class InputSourceActionHandler: ActionHandler {
    let service: InputSourceService
    init(service: InputSourceService) { self.service = service }

    func execute(_ action: ShortcutAction, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let id = action.inputSourceID, !id.isEmpty else {
            completion(
                .failure(ActionFailure("Choose an installed input source for this mapping in Settings.")))
            return
        }
        do {
            try service.select(id: id)
            completion(.success(()))
        } catch { completion(.failure(error)) }
    }
}

@MainActor
private final class LaunchApplicationActionHandler: ActionHandler {
    func execute(_ action: ShortcutAction, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let path = action.applicationPath, path.hasPrefix("/") else {
            completion(.failure(ActionFailure("Choose an application for this mapping in Settings.")))
            return
        }
        let url = URL(fileURLWithPath: path)
        guard url.pathExtension.lowercased() == "app", FileManager.default.fileExists(atPath: path),
            Bundle(url: url)?.executableURL != nil
        else {
            completion(
                .failure(
                    ActionFailure("The selected application is unavailable. Choose its .app bundle again.")))
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error { completion(.failure(error)) } else { completion(.success(())) }
            }
        }
    }
}

@MainActor
private final class OpenURLActionHandler: ActionHandler {
    func execute(_ action: ShortcutAction, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let text = action.url?.trimmingCharacters(in: .whitespacesAndNewlines),
            let components = URLComponents(string: text),
            let scheme = components.scheme?.lowercased(),
            ["http", "https", "mailto"].contains(scheme),
            let url = components.url,
            (scheme == "mailto" ? !components.path.isEmpty : !(components.host ?? "").isEmpty)
        else {
            completion(.failure(ActionFailure("Enter a valid http, https, or mailto URL in Settings.")))
            return
        }
        if NSWorkspace.shared.open(url) {
            completion(.success(()))
        } else {
            completion(
                .failure(ActionFailure("macOS could not open this URL. Check its default application.")))
        }
    }
}

@MainActor
private final class SendShortcutActionHandler: ActionHandler {
    private struct Pending {
        let id: UUID
        let combination: KeyCombination
        let targetPID: pid_t?
        let completion: (Result<Void, Error>) -> Void
    }

    private var downKeys = Set<UInt16>()
    private var pending: Pending?
    private var deadline: DispatchWorkItem?
    private var deliveryScheduled = false

    func execute(_ action: ShortcutAction, completion: @escaping (Result<Void, Error>) -> Void) {
        guard ActionExecutor.accessibilityPermissionGranted else {
            completion(
                .failure(
                    ActionFailure(
                        "Sending a shortcut requires Accessibility permission. Grant it explicitly in Settings, then retry."
                    )))
            return
        }
        guard let combination = action.shortcut, combination.isValid,
            PhysicalModifier(keyCode: combination.keyCode) == nil,
            ![UInt16(57), UInt16(63)].contains(combination.keyCode),
            combination.modifiers.subtracting([.shift, .control, .option, .command, .function]).isEmpty
        else {
            completion(
                .failure(ActionFailure("Configure a valid key and modifiers for the shortcut to send.")))
            return
        }
        cancelPendingAction()
        let id = UUID()
        pending = Pending(
            id: id, combination: combination,
            targetPID: NSWorkspace.shared.frontmostApplication?.processIdentifier,
            completion: completion)
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.pending?.id == id else { return }
            self.finish(
                .failure(
                    ActionFailure(
                        "The shortcut was canceled because its trigger keys were not released within five seconds."
                    )))
        }
        deadline = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)
        scheduleDeliveryIfReleased()
    }

    func observe(_ event: KeyboardEvent) {
        switch event.kind {
        case .keyDown:
            downKeys.insert(event.keyCode)
            if pending != nil && !event.isRepeat {
                finish(.failure(ActionFailure("The pending shortcut was canceled by another key press.")))
            }
        case .keyUp:
            downKeys.remove(event.keyCode)
            scheduleDeliveryIfReleased()
        case .modifierDown:
            if pending != nil {
                finish(
                    .failure(ActionFailure("The pending shortcut was canceled by another modifier press.")))
            }
        case .modifierUp:
            scheduleDeliveryIfReleased()
        case .mouseActivity:
            if pending != nil {
                finish(.failure(ActionFailure("The pending shortcut was canceled by mouse activity.")))
            }
        case .reset:
            downKeys.removeAll(keepingCapacity: true)
            cancelPendingAction()
        }
    }

    func cancelPendingAction() {
        if pending != nil { finish(.failure(ActionFailure("The pending shortcut was canceled."))) }
    }

    private var physicalKeysAreReleased: Bool {
        downKeys.isEmpty
            && EventMonitor.modifiers(
                from: CGEventSource.flagsState(.hidSystemState),
                physicalFunctionDown: CGEventSource.keyState(.hidSystemState, key: 63)
            ).isEmpty
    }

    private func scheduleDeliveryIfReleased() {
        guard pending != nil, !deliveryScheduled, physicalKeysAreReleased else { return }
        deliveryScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.deliveryScheduled = false
            guard let pending = self.pending, self.physicalKeysAreReleased else { return }
            // Snapshot once per delivery attempt, outside the event callback. A key held before
            // monitoring started may never have produced a keyDown in our observed stream.
            let alreadyHeld = (UInt16(0)...127).filter { code in
                PhysicalModifier(keyCode: code) == nil && code != 57 && code != 63
                    && CGEventSource.keyState(.hidSystemState, key: code)
            }
            guard alreadyHeld.isEmpty else {
                self.downKeys.formUnion(alreadyHeld)
                return  // A real keyUp event will retry; there is no polling.
            }
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pending.targetPID else {
                self.finish(
                    .failure(
                        ActionFailure("The shortcut was canceled because the frontmost application changed."))
                )
                return
            }
            do {
                try self.post(pending.combination)
                self.finish(.success(()))
            } catch { self.finish(.failure(error)) }
        }
    }

    private func finish(_ result: Result<Void, Error>) {
        let completion = pending?.completion
        pending = nil
        deadline?.cancel()
        deadline = nil
        // Completion callbacks can update UI; dispatch them outside the event callback.
        if let completion { DispatchQueue.main.async { completion(result) } }
    }

    private func post(_ combination: KeyCombination) throws {
        guard ActionExecutor.accessibilityPermissionGranted,
            let source = CGEventSource(stateID: .privateState)
        else {
            throw ActionFailure(
                "macOS denied permission to send the shortcut. Check Accessibility permission.")
        }
        let definitions: [(KeyModifiers, CGKeyCode, CGEventFlags)] = [
            (.control, 59, .maskControl), (.option, 58, .maskAlternate),
            (.shift, 56, .maskShift), (.command, 55, .maskCommand),
            (.function, 63, .maskSecondaryFn),
        ]
        let selected = definitions.filter { combination.modifiers.contains($0.0) }
        var flags: CGEventFlags = []
        var events: [CGEvent] = []
        func makeEvent(key: CGKeyCode, down: Bool, modifier: Bool = false) throws -> CGEvent {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else {
                throw ActionFailure("macOS could not allocate a keyboard event.")
            }
            if modifier { event.type = .flagsChanged }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: shortcutterSyntheticEventTag)
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            return event
        }
        // Allocate the whole sequence before posting so an allocation failure cannot leave a modifier down.
        for (_, code, flag) in selected {
            flags.insert(flag)
            events.append(try makeEvent(key: code, down: true, modifier: true))
        }
        events.append(try makeEvent(key: combination.keyCode, down: true))
        events.append(try makeEvent(key: combination.keyCode, down: false))
        for (_, code, flag) in selected.reversed() {
            flags.remove(flag)
            events.append(try makeEvent(key: code, down: false, modifier: true))
        }
        for event in events { event.post(tap: .cgSessionEventTap) }
    }
}
