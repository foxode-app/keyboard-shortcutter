import AppKit
import Combine
import ServiceManagement
import SwiftUI

#if canImport(ShortcutCore)
import ShortcutCore
#endif

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var rules: [ShortcutRule] = []
    @Published private(set) var sources: [InputSourceService.Source] = []
    @Published private(set) var isMonitoring = false
    @Published private(set) var disableOptionModifiers = false
    @Published private(set) var isOptionSuppressionActive = false
    @Published private(set) var isFunctionKeySuppressionActive = false
    @Published private(set) var isPaused = UserDefaults.standard.bool(forKey: "monitoringPaused")
    @Published private(set) var hasMonitoringPermission = false
    @Published private(set) var hasAccessibilityPermission = false
    @Published private(set) var loginEnabled = false
    @Published private(set) var loginNeedsApproval = false
    @Published private(set) var configurationAvailable = false
    @Published var status = "準備中"
    @Published var errorMessage: String?
    @Published var isRecording = false {
        didSet {
            guard oldValue != isRecording else { return }
            invalidatePendingEvents()
            if isRecording {
                monitor.stop()
                isMonitoring = false
            } else {
                resumeIfPossible()
            }
        }
    }

    let configurationURL: URL
    private let store: ConfigurationStore
    private let inputSources = InputSourceService()
    private lazy var executor = ActionExecutor(inputSourceService: inputSources)
    private lazy var monitor: EventMonitor = EventMonitor(
        onEvent: { [weak self] event in self?.receive(event) ?? false },
        onStatusChange: { [weak self] message in
            self?.status = message
            self?.isMonitoring = self?.monitor.isRunning ?? false
            self?.isOptionSuppressionActive = self?.monitor.isSuppressingOption ?? false
            self?.isFunctionKeySuppressionActive = self?.monitor.isSuppressingFunctionKeys ?? false
        }
    )
    private var matcher = TriggerMatcher()
    private var generation = 0
    private var observations: [NSObjectProtocol] = []
    private var settingsWindow: SettingsWindowController?
    private var isStarted = false
    private(set) var isFirstLaunch = false

    init(configurationURL: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url =
            configurationURL
            ?? support
            .appendingPathComponent("KeyboardShortcutter", isDirectory: true)
            .appendingPathComponent("settings.json")
        self.configurationURL = url
        store = ConfigurationStore(url: url)
    }

    var conflicts: [RuleConflict] { TriggerMatcher.conflicts(in: rules) }
    var hasFunctionKeyMappings: Bool {
        rules.contains { rule in
            guard rule.isEnabled, case .keyboardShortcut(let combination) = rule.trigger else {
                return false
            }
            return FunctionKey.contains(combination.keyCode)
        }
    }
    var requiresAccessibilityForMonitoring: Bool { disableOptionModifiers || hasFunctionKeyMappings }
    var hasRequiredMonitoringPermission: Bool {
        requiresAccessibilityForMonitoring ? hasAccessibilityPermission : hasMonitoringPermission
    }
    var statusTitle: String {
        if isPaused { return "一時停止中" }
        if isRecording { return "キーを記録中" }
        if isFunctionKeySuppressionActive && isOptionSuppressionActive { return "監視中・Fキー設定・Option無効化中" }
        if isFunctionKeySuppressionActive { return "監視中・Fキー設定中" }
        if isOptionSuppressionActive { return "監視中・Option無効化中" }
        return isMonitoring ? "監視中" : "監視停止"
    }

    func start() {
        guard !isStarted else { return }
        isStarted = true
        refreshSystemState()
        loadConfiguration()
        let center = NotificationCenter.default
        observations.append(
            center.addObserver(
                forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refreshSystemState()
                    self?.resumeIfPossible()
                }
            })
        resumeIfPossible()
        if isFirstLaunch || !hasRequiredMonitoringPermission || !configurationAvailable
            || (disableOptionModifiers && !isOptionSuppressionActive)
            || (hasFunctionKeyMappings && !isFunctionKeySuppressionActive)
        {
            showSettings()
        }
    }

    func stop() {
        isStarted = false
        monitor.stop()
        invalidatePendingEvents()
        isMonitoring = false
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
    }

    func refreshSystemState() {
        sources = inputSources.enumerate()
        hasMonitoringPermission = EventMonitor.monitoringPermissionGranted
        hasAccessibilityPermission = EventMonitor.interceptionPermissionGranted
        loginEnabled = SMAppService.mainApp.status == .enabled
        loginNeedsApproval = SMAppService.mainApp.status == .requiresApproval
    }

    func loadConfiguration() {
        do {
            if let configuration = try store.load() {
                rules = configuration.rules
                disableOptionModifiers = configuration.disableOptionModifiers
            } else {
                isFirstLaunch = true
                let japanese = sources.first {
                    $0.languages.contains(where: { $0.hasPrefix("ja") })
                        && ($0.name.localizedCaseInsensitiveContains("hiragana")
                            || $0.name.contains("ひらがな"))
                }
                let english =
                    sources.first { $0.name.caseInsensitiveCompare("ABC") == .orderedSame }
                    ?? sources.first { $0.languages.contains(where: { $0.hasPrefix("en") }) }
                let configuration = ConfigurationStore.defaultConfiguration(
                    japaneseSourceID: japanese?.id, englishSourceID: english?.id
                )
                try store.save(configuration)
                rules = configuration.rules
                disableOptionModifiers = configuration.disableOptionModifiers
            }
            configurationAvailable = true
            errorMessage = nil
            invalidatePendingEvents()
        } catch {
            configurationAvailable = false
            monitor.stop()
            isMonitoring = false
            errorMessage = "設定を読み込めません。元のファイルは保持されています。\n\(error.localizedDescription)"
        }
    }

    @discardableResult
    func saveRule(_ rule: ShortcutRule) -> Bool {
        saveRules([rule])
    }

    /// Saves related additions or edits together, preserving all unrelated mappings.
    @discardableResult
    func saveRules(_ changes: [ShortcutRule]) -> Bool {
        var updated = rules
        for rule in changes {
            if let index = updated.firstIndex(where: { $0.id == rule.id }) {
                updated[index] = rule
            } else {
                updated.append(rule)
            }
        }
        return persist(updated)
    }

    func deleteRule(_ rule: ShortcutRule) { _ = persist(rules.filter { $0.id != rule.id }) }

    func toggleRule(_ rule: ShortcutRule) {
        var updated = rule
        updated.isEnabled.toggle()
        _ = saveRule(updated)
    }

    func setOptionModifierSuppression(_ enabled: Bool) {
        guard enabled != disableOptionModifiers else { return }
        _ = persist(rules, disableOptionModifiers: enabled)
    }

    func validationMessage(for action: ShortcutAction) -> String? {
        RuleActionValidator.validate(action, availableInputSourceIDs: Set(sources.map(\.id)))
    }

    func togglePaused() {
        isPaused.toggle()
        UserDefaults.standard.set(isPaused, forKey: "monitoringPaused")
        invalidatePendingEvents()
        if isPaused {
            monitor.stop()
            isMonitoring = false
            status = "一時停止中"
        } else {
            resumeIfPossible()
        }
    }

    func requestMonitoringPermission() {
        _ = EventMonitor.requestMonitoringPermission()
        refreshSystemState()
        resumeIfPossible()
    }

    func requestAccessibilityPermission() {
        ActionExecutor.requestAccessibilityPermission()
        refreshSystemState()
        resumeIfPossible()
    }

    func retryMonitoring() {
        monitor.stop()
        invalidatePendingEvents()
        refreshSystemState()
        resumeIfPossible()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshSystemState()
        } catch {
            errorMessage = "ログイン時の起動設定に失敗しました: \(error.localizedDescription)"
        }
    }

    func openPrivacySettings(accessibility: Bool = false) {
        let pane = accessibility ? "Privacy_Accessibility" : "Privacy_ListenEvent"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    func showSettings() {
        refreshSystemState()
        if settingsWindow == nil { settingsWindow = SettingsWindowController(model: self) }
        settingsWindow?.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.window?.makeKeyAndOrderFront(nil)
    }

    private func persist(_ updated: [ShortcutRule], disableOptionModifiers: Bool? = nil) -> Bool {
        guard configurationAvailable else { return false }
        let suppressOption = disableOptionModifiers ?? self.disableOptionModifiers
        do {
            try store.save(RulesConfiguration(rules: updated, disableOptionModifiers: suppressOption))
            rules = updated
            self.disableOptionModifiers = suppressOption
            errorMessage = nil
            invalidatePendingEvents()
            resumeIfPossible()
            return true
        } catch {
            errorMessage = "設定を保存できません: \(error.localizedDescription)"
            return false
        }
    }

    private func resumeIfPossible() {
        guard isStarted, configurationAvailable, !isPaused, !isRecording else { return }
        guard requiresAccessibilityForMonitoring || EventMonitor.monitoringPermissionGranted else {
            monitor.stop()
            isMonitoring = false
            status = "入力監視の権限を設定してください"
            return
        }
        guard !requiresAccessibilityForMonitoring || EventMonitor.interceptionPermissionGranted else {
            monitor.stop()
            isMonitoring = false
            status = "Fキーの割り当て・Option無効化にはアクセシビリティ権限が必要です。「権限と起動」で許可してください。"
            return
        }
        if !monitor.isRunning || monitor.isSuppressingOption != disableOptionModifiers
            || monitor.isSuppressingFunctionKeys != hasFunctionKeyMappings
        {
            isMonitoring = monitor.start(
                disableOptionModifiers: disableOptionModifiers, interceptFunctionKeys: hasFunctionKeyMappings)
            isOptionSuppressionActive = monitor.isSuppressingOption
            isFunctionKeySuppressionActive = monitor.isSuppressingFunctionKeys
        }
    }

    private func invalidatePendingEvents() {
        generation += 1
        matcher.reset()
        executor.cancelPendingAction()
        executor.observe(KeyboardEvent(kind: .reset))
    }

    private func receive(_ event: KeyboardEvent) -> Bool {
        // Invalidate actions queued before a tap reset, sleep, or synthetic-event boundary.
        if event.kind == .reset { generation += 1 }
        guard !isPaused, !isRecording, configurationAvailable else { return false }
        executor.observe(event)
        let matched = matcher.process(event, rules: rules)
        guard !matched.isEmpty else { return false }
        let currentGeneration = generation
        // Defer all TIS / workspace / UI work until after the event-tap callback returns.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.generation == currentGeneration else { return }
            for rule in matched {
                if let problem = self.validationMessage(for: rule.action) {
                    self.errorMessage = "\(rule.name): \(problem)"
                    continue
                }
                self.executor.execute(rule.action) { [weak self] result in
                    if case .failure(let error) = result {
                        self?.errorMessage = "\(rule.name): \(error.localizedDescription)"
                    }
                }
            }
        }
        return event.kind == .keyDown && FunctionKey.contains(event.keyCode)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    private weak var model: AppModel?

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false
        )
        window.title = "Keyboard Shortcutter — 設定"
        let hostingController = NSHostingController(rootView: SettingsView(model: model))
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        window.contentMinSize = NSSize(width: 760, height: 560)
        window.setContentSize(NSSize(width: 880, height: 660))
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    required init?(coder: NSCoder) { nil }

    func windowWillClose(_ notification: Notification) { model?.isRecording = false }
}
