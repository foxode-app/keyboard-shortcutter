import AppKit
import ApplicationServices
import Carbon
import CoreGraphics

#if canImport(ShortcutCore)
import ShortcutCore
#endif

/// Identifies events posted by this process so mappings cannot recursively trigger themselves.
let shortcutterSyntheticEventTag: Int64 = 0x4B534354

@MainActor
final class EventMonitor {
    private let onEvent: (KeyboardEvent) -> Bool
    private let onStatusChange: (String) -> Void
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var pressedModifiers = Set<UInt16>()
    private var pressedKeys = Set<UInt16>()
    private var functionIsDown = false
    private var observers: [NSObjectProtocol] = []
    private var shouldRun = false
    private var recoveryTimes: [TimeInterval] = []
    private var stateSnapshotPending = false
    private var disableOptionModifiers = false
    private var interceptFunctionKeys = false
    private let optionFilter = OptionEventFilter()
    private var functionKeyFilter = FunctionKeyEventFilter()
    private(set) var isRunning = false

    static var monitoringPermissionGranted: Bool { CGPreflightListenEventAccess() }
    static var interceptionPermissionGranted: Bool { AXIsProcessTrusted() }
    var isSuppressingOption: Bool { isRunning && disableOptionModifiers }
    var isSuppressingFunctionKeys: Bool { isRunning && interceptFunctionKeys }

    @discardableResult
    static func requestMonitoringPermission() -> Bool { CGRequestListenEventAccess() }

    init(onEvent: @escaping (KeyboardEvent) -> Bool, onStatusChange: @escaping (String) -> Void) {
        self.onEvent = onEvent
        self.onStatusChange = onStatusChange
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.tearDownTap()
                        self?.onStatusChange("Monitoring suspended while the Mac is asleep or locked.")
                    }
                })
        }
        for name in [NSWorkspace.didWakeNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated {
                        guard let self, self.shouldRun else { return }
                        _ = self.start(
                            disableOptionModifiers: self.disableOptionModifiers,
                            interceptFunctionKeys: self.interceptFunctionKeys)
                    }
                })
        }
    }

    deinit {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let tap { CFMachPortInvalidate(tap) }
    }

    @discardableResult
    func start(disableOptionModifiers: Bool = false, interceptFunctionKeys: Bool = false) -> Bool {
        shouldRun = true
        if isRunning && self.disableOptionModifiers == disableOptionModifiers
            && self.interceptFunctionKeys == interceptFunctionKeys
        {
            return true
        }
        tearDownTap()
        self.disableOptionModifiers = disableOptionModifiers
        self.interceptFunctionKeys = interceptFunctionKeys
        guard permissionGranted else {
            onStatusChange(
                requiresInterception
                    ? "F-key remapping and Option suppression require Accessibility permission. Enable Keyboard Shortcutter in System Settings, then retry or relaunch."
                    : "Input Monitoring permission is required. Enable Keyboard Shortcutter in System Settings, then retry or relaunch."
            )
            return false
        }
        guard !disableOptionModifiers || !Self.optionIsHeld else {
            onStatusChange("Release both Option keys, then retry to enable Option suppression safely.")
            return false
        }
        let eventTypes: [CGEventType] = [
            .keyDown, .keyUp, .flagsChanged,
            .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp,
            .otherMouseDown, .otherMouseUp, .scrollWheel,
            .mouseMoved, .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
        ]
        let mask = eventTypes.reduce(CGEventMask(0)) { $0 | (CGEventMask(1) << $1.rawValue) }
        guard
            let newTap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap,
                options: requiresInterception ? .defaultTap : .listenOnly,
                eventsOfInterest: mask,
                callback: { _, type, event, context in
                    guard let context else { return Unmanaged.passUnretained(event) }
                    // This tap's run-loop source is installed exclusively on the main run loop.
                    return MainActor.assumeIsolated {
                        guard
                            let result = Unmanaged<EventMonitor>.fromOpaque(context).takeUnretainedValue()
                                .receive(type: type, event: event)
                        else { return nil }
                        // Quartz releases a newly returned event after delivering it.
                        return result === event
                            ? Unmanaged.passUnretained(result) : Unmanaged.passRetained(result)
                    }
                }, userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            onStatusChange(
                requiresInterception
                    ? "macOS could not start key remapping. Check Accessibility permission, close secure password entry, then retry."
                    : "macOS could not start the passive event monitor. Check Input Monitoring permission, close secure password entry, then retry."
            )
            return false
        }
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, newTap, 0) else {
            CFMachPortInvalidate(newTap)
            onStatusChange("The event monitor run-loop source could not be created.")
            return false
        }
        tap = newTap
        runLoopSource = source
        // Already-held keys must never become new modifier-only taps after a restart.
        snapshotHeldKeys()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: newTap, enable: true)
        isRunning = CGEvent.tapIsEnabled(tap: newTap)
        if isRunning {
            if interceptFunctionKeys {
                onStatusChange(
                    disableOptionModifiers
                        ? "Monitoring is active; assigned F keys are remapped and both Option keys are disabled."
                        : "Monitoring is active; assigned F keys are remapped. Unassigned keys retain their normal behavior."
                )
            } else {
                onStatusChange(
                    disableOptionModifiers
                        ? "Monitoring is active; the normal function of both Option keys is disabled."
                        : "Monitoring is active (passive; original keys are preserved).")
            }
        } else {
            tearDownTap()
            onStatusChange("macOS did not enable the monitor. Check the required permission and retry.")
        }
        return isRunning
    }

    func stop() {
        shouldRun = false
        recoveryTimes.removeAll()
        tearDownTap()
        onStatusChange("Monitoring is paused.")
    }

    private func tearDownTap() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap { CFMachPortInvalidate(tap) }
        runLoopSource = nil
        tap = nil
        isRunning = false
        stateSnapshotPending = false
        resetState()
    }

    private func resetState(resetFunctionKeys: Bool = true) {
        pressedModifiers.removeAll(keepingCapacity: true)
        pressedKeys.removeAll(keepingCapacity: true)
        functionIsDown = false
        if resetFunctionKeys { functionKeyFilter.reset() }
        _ = onEvent(KeyboardEvent(kind: .reset))
    }

    private func snapshotHeldKeys() {
        pressedModifiers.removeAll(keepingCapacity: true)
        pressedKeys.removeAll(keepingCapacity: true)
        // Read hardware state only; combined-session state also includes synthetic events.
        for code in Self.physicalModifierMasks.keys where CGEventSource.keyState(.hidSystemState, key: code) {
            pressedModifiers.insert(code)
        }
        functionIsDown = pressedModifiers.contains(63)
        for code in UInt16(0)...127 where Self.physicalModifierMasks[code] == nil && code != 57 && code != 63
        {
            if CGEventSource.keyState(.hidSystemState, key: code) { pressedKeys.insert(code) }
        }
    }

    private func scheduleStateSnapshot() {
        guard !stateSnapshotPending else { return }
        stateSnapshotPending = true
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stateSnapshotPending else { return }
            self.stateSnapshotPending = false
            if self.isRunning { self.snapshotHeldKeys() }
        }
    }

    private func receive(type: CGEventType, event: CGEvent) -> CGEvent? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            resetState()
            isRunning = false
            // Recovery and reporting run outside the latency-sensitive tap callback.
            DispatchQueue.main.async { [weak self] in
                self?.recover(disabledByUserInput: type == .tapDisabledByUserInput)
            }
            return event
        }
        if event.getIntegerValueField(.eventSourceUserData) == shortcutterSyntheticEventTag {
            // App-generated events bypass matching and filtering. Keep ownership of
            // physical F-key presses so their later releases cannot leak downstream.
            resetState(resetFunctionKeys: false)
            scheduleStateSnapshot()
            return event
        }
        // Even during a matcher reset, outgoing events must still have Option removed.
        let matched = !stateSnapshotPending && observePhysicalEvent(type: type, event: event)
        if functionKeyFilter.shouldConsume(
            event, type: type, enabled: interceptFunctionKeys, matched: matched)
        {
            return nil
        }
        do {
            return try optionFilter.apply(to: event, type: type, enabled: disableOptionModifiers)
        } catch {
            // Never forward a stale Option character if allocation fails. Report and stop
            // outside the callback so the user can explicitly retry the failed monitor.
            DispatchQueue.main.async { [weak self] in
                self?.tearDownTap()
                self?.onStatusChange(
                    "Option suppression could not transform a key event. Monitoring stopped; retry to resume."
                )
            }
            return nil
        }
    }

    private func observePhysicalEvent(type: CGEventType, event: CGEvent) -> Bool {
        if type == .flagsChanged && event.getIntegerValueField(.keyboardEventKeycode) == 63 {
            functionIsDown = event.flags.contains(.maskSecondaryFn)
        }
        // Arrow/navigation/function keys can carry maskSecondaryFn without a physical Fn press.
        let modifiers = Self.modifiers(from: event.flags, physicalFunctionDown: functionIsDown)
        switch type {
        case .keyDown, .keyUp:
            let code = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            if type == .keyDown { pressedKeys.insert(code) } else { pressedKeys.remove(code) }
            return onEvent(
                KeyboardEvent(
                    kind: type == .keyDown ? .keyDown : .keyUp,
                    keyCode: code,
                    modifiers: modifiers,
                    isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
                ))
        case .flagsChanged:
            let code = UInt16(clamping: event.getIntegerValueField(.keyboardEventKeycode))
            guard let mask = Self.physicalModifierMasks[code] else {
                // Caps Lock reports a toggle, not a reliable physical release.
                _ = onEvent(KeyboardEvent(kind: .mouseActivity, modifiers: modifiers))
                return false
            }
            let down = event.flags.rawValue & mask != 0
            let wasDown = pressedModifiers.contains(code)
            guard down != wasDown else { return false }
            if down { pressedModifiers.insert(code) } else { pressedModifiers.remove(code) }
            _ = onEvent(
                KeyboardEvent(kind: down ? .modifierDown : .modifierUp, keyCode: code, modifiers: modifiers))
            if down
                && (!pressedKeys.isEmpty || pressedModifiers.count > 1
                    || Self.mouseButtons.contains { CGEventSource.buttonState(.hidSystemState, button: $0) })
            {
                _ = onEvent(KeyboardEvent(kind: .mouseActivity, modifiers: modifiers))
            }
        default:
            // Ignore routine pointer movement when there cannot be a modifier-only candidate.
            if type != .mouseMoved || !pressedModifiers.isEmpty {
                _ = onEvent(KeyboardEvent(kind: .mouseActivity, modifiers: modifiers))
            }
        }
        return false
    }

    private func recover(disabledByUserInput: Bool) {
        guard shouldRun, let tap else { return }
        let now = ProcessInfo.processInfo.systemUptime
        recoveryTimes = recoveryTimes.filter { now - $0 < 10 }
        recoveryTimes.append(now)
        guard !disabledByUserInput, recoveryTimes.count <= 3, permissionGranted else {
            tearDownTap()
            onStatusChange(
                "macOS disabled monitoring. Check permissions and secure input, then pause and resume to retry."
            )
            return
        }
        guard !disableOptionModifiers || !Self.optionIsHeld else {
            tearDownTap()
            onStatusChange(
                "Release both Option keys, then pause and resume to restore Option suppression safely.")
            return
        }
        snapshotHeldKeys()
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = CGEvent.tapIsEnabled(tap: tap)
        onStatusChange(
            isRunning
                ? "Monitoring recovered after an event-tap timeout."
                : "Monitoring could not recover. Pause and resume to retry.")
    }

    private var permissionGranted: Bool {
        requiresInterception ? Self.interceptionPermissionGranted : Self.monitoringPermissionGranted
    }

    private var requiresInterception: Bool { disableOptionModifiers || interceptFunctionKeys }

    private static var optionIsHeld: Bool {
        CGEventSource.keyState(.hidSystemState, key: 58)
            || CGEventSource.keyState(.hidSystemState, key: 61)
            || CGEventSource.flagsState(.hidSystemState).contains(.maskAlternate)
    }

    static func modifiers(from flags: CGEventFlags, physicalFunctionDown: Bool? = nil) -> KeyModifiers {
        var result: KeyModifiers = []
        if flags.contains(.maskShift) { result.insert(.shift) }
        if flags.contains(.maskControl) { result.insert(.control) }
        if flags.contains(.maskAlternate) { result.insert(.option) }
        if flags.contains(.maskCommand) { result.insert(.command) }
        if physicalFunctionDown ?? flags.contains(.maskSecondaryFn) { result.insert(.function) }
        return result
    }

    // NX_DEVICE*KEYMASK values from the SDK's IOKit/hidsystem/IOLLEvent.h.
    // Aggregate maskAlternate/maskCommand cannot distinguish two sides held together.
    private static let physicalModifierMasks: [UInt16: UInt64] = [
        59: 0x00000001, 56: 0x00000002, 60: 0x00000004,
        55: 0x00000008, 54: 0x00000010, 58: 0x00000020,
        61: 0x00000040, 62: 0x00002000,
        // Fn has one aggregate physical transition; it cancels taps and releases queued shortcuts.
        63: CGEventFlags.maskSecondaryFn.rawValue,
    ]

    private static let mouseButtons = (0..<32).compactMap { CGMouseButton(rawValue: UInt32($0)) }
}
