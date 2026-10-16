import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

#if canImport(ShortcutCore)
import ShortcutCore
#endif

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var editingRule: ShortcutRule?
    @State private var deletingRule: ShortcutRule?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Keyboard Shortcutter").font(.title2.bold())
                    Label(model.statusTitle, systemImage: model.isMonitoring ? "circle.fill" : "pause.circle")
                        .foregroundStyle(model.isMonitoring ? .green : .secondary)
                        .font(.caption)
                }
                Spacer()
                Button(model.isPaused ? "再開" : "一時停止") { model.togglePaused() }
            }
            if let error = model.errorMessage {
                HStack(alignment: .top) {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text(error).font(.callout).textSelection(.enabled)
                    Spacer()
                    Button {
                        model.errorMessage = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless).help("エラー表示を閉じる")
                }
                .padding(10).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            TabView {
                FunctionKeySettingsView(
                    model: model, onEdit: { editingRule = $0 },
                    onDelete: { deletingRule = $0 }, actionSummary: actionSummary
                ).tabItem { Label("Fキー", systemImage: "f.square") }
                mappings.tabItem { Label("マッピング", systemImage: "keyboard") }
                permissions.tabItem { Label("権限と起動", systemImage: "lock.shield") }
            }
            Text(monitoringExplanation)
                .font(.caption).foregroundStyle(.secondary)
            Link(FoxodeWebsite.title, destination: FoxodeWebsite.productURL)
                .font(.caption)
        }
        .padding(20)
        .sheet(item: $editingRule) { rule in
            RuleEditor(model: model, rule: rule)
        }
        .alert(
            "マッピングを削除しますか？",
            isPresented: Binding(
                get: { deletingRule != nil }, set: { if !$0 { deletingRule = nil } }
            )
        ) {
            Button("削除", role: .destructive) {
                if let rule = deletingRule { model.deleteRule(rule) }
                deletingRule = nil
            }
            Button("キャンセル", role: .cancel) { deletingRule = nil }
        } message: {
            Text(deletingRule?.name ?? "")
        }
    }

    private var mappings: some View {
        VStack(alignment: .leading, spacing: 12) {
            optionSuppressionSettings
            HStack {
                Text("\(model.rules.count)件のマッピング").font(.headline)
                Spacer()
                Button {
                    editingRule = ShortcutRule(
                        name: "新しいマッピング", trigger: .modifierTap(.leftOption),
                        action: ShortcutAction(kind: "inputSource")
                    )
                } label: {
                    Label("マッピングを追加", systemImage: "plus")
                }
                .disabled(!model.configurationAvailable)
            }
            if !model.configurationAvailable {
                Text("設定ファイルの読み込みに失敗したため編集を停止しています。ファイルを修復して再読み込みしてください。")
                    .foregroundStyle(.orange)
                Button("設定ファイルを再読み込み") {
                    model.loadConfiguration(); model.retryMonitoring()
                }
            }
            if model.rules.isEmpty && model.configurationAvailable {
                VStack(spacing: 10) {
                    Image(systemName: "keyboard").font(.largeTitle)
                    Text("マッピングを追加してキーに動作を割り当てます。")
                }.frame(maxWidth: .infinity, maxHeight: .infinity).foregroundStyle(.secondary)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.rules) { rule in ruleRow(rule) }
                    }
                }
            }
            Text("同じトリガーの有効なルールは競合として両方停止します。他のアプリやOSのショートカットとの競合は検出できません。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
    }

    private var monitoringExplanation: String {
        if !model.isMonitoring {
            return "監視停止中：登録した割り当ては実行しません。入力内容は記録しません。"
        }
        if model.isFunctionKeySuppressionActive {
            return model.isOptionSuppressionActive
                ? "Fキー割り当て・Option無効化が動作中です。入力内容は記録しません。"
                : "Fキー割り当てが動作中です。割り当てのないキーは通常どおり動作します。入力内容は記録しません。"
        }
        if model.isOptionSuppressionActive {
            return "Option無効化中：他のアプリに届くキーやマウス操作からOptionの効果を除きます。入力内容は記録しません。"
        }
        return "受動監視：元のキー操作はそのままアプリやmacOSに届きます。入力内容は記録しません。"
    }

    private var optionSuppressionSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(
                "Option（Alt）本来の動作を無効にする",
                isOn: Binding(
                    get: { model.disableOptionModifiers },
                    set: { model.setOptionModifierSuppression($0) }
                )
            )
            .toggleStyle(.switch)
            .disabled(!model.configurationAvailable)
            Text("左右両方のOptionを対象にします。単独タップの入力切替は維持し、Option＋文字やクリックはOptionなしで他のアプリに届きます。切替時はOptionを離してください。")
                .font(.caption).foregroundStyle(.secondary)
            if model.disableOptionModifiers {
                Label(
                    model.isOptionSuppressionActive ? "Option本来の動作を無効化中" : "現在は無効化されていません",
                    systemImage: model.isOptionSuppressionActive
                        ? "checkmark.circle" : "exclamationmark.circle"
                ).font(.callout).foregroundStyle(model.isOptionSuppressionActive ? .green : .orange)
                if !model.isOptionSuppressionActive {
                    Text(model.status).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        if !model.hasAccessibilityPermission {
                            Button("アクセシビリティを許可…") { model.requestAccessibilityPermission() }
                        }
                        Button("状態を再確認") { model.retryMonitoring() }
                    }
                }
                Text("一時停止・終了・キー記録中は通常のOptionに戻ります。アプリのルールに登録したOptionの組み合わせと、送信アクションのOptionは有効です。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func ruleRow(_ rule: ShortcutRule) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 12) {
                Toggle(
                    "有効",
                    isOn: Binding(
                        get: { rule.isEnabled }, set: { _ in model.toggleRule(rule) }
                    )
                ).labelsHidden().toggleStyle(.switch).accessibilityLabel("\(rule.name)を有効にする")
                VStack(alignment: .leading, spacing: 5) {
                    Text(rule.name).font(.headline)
                    Text("\(rule.trigger.title) → \(actionSummary(rule.action))")
                        .font(.callout).foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("編集") { editingRule = rule }
                Button {
                    deletingRule = rule
                } label: {
                    Image(systemName: "trash")
                }
                .help("マッピングを削除")
            }
            if let conflict = model.conflicts.first(where: { $0.ruleIDs.contains(rule.id) }) {
                Label(conflict.message, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            if let issue = model.validationMessage(for: rule.action) {
                Label(issue, systemImage: "exclamationmark.circle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .disabled(!model.configurationAvailable)
    }

    private func actionSummary(_ action: ShortcutAction) -> String {
        switch action.kind {
        case "inputSource":
            return model.sources.first(where: { $0.id == action.inputSourceID })?.name ?? "入力ソース未設定 / 利用不可"
        case "launchApplication":
            return action.applicationPath.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "アプリ未設定"
        case "openURL": return action.url ?? "URL未設定"
        case "sendShortcut": return "送信: \(action.shortcut?.title ?? "未設定")"
        case "systemAction": return action.resolvedSystemAction?.title ?? "システム操作未設定 / 未対応"
        default: return "未対応のアクション: \(action.kind)"
        }
    }

    private var permissions: some View {
        Form {
            Section("入力監視（通常のキー監視）") {
                Label(
                    model.hasMonitoringPermission ? "許可済み" : "許可が必要です",
                    systemImage: model.hasMonitoringPermission ? "checkmark.circle" : "lock")
                Text(
                    "Fキーへの割り当てとOption無効化を使わない通常の監視に必要です。システム設定 → プライバシーとセキュリティ → 入力監視で許可してください。Fキーへの割り当て、またはOption無効化を使うときの監視は、下のアクセシビリティ権限を使用します。許可後に再起動が必要な場合があります。"
                )
                .font(.callout)
                HStack {
                    Button("入力監視を許可…") { model.requestMonitoringPermission() }
                    Button("システム設定を開く") { model.openPrivacySettings() }
                    Button("状態を再確認") { model.retryMonitoring() }
                }
                Text(model.status).font(.caption).foregroundStyle(.secondary)
            }
            Section("アクセシビリティ") {
                Label(
                    model.hasAccessibilityPermission ? "許可済み" : "未許可",
                    systemImage: model.hasAccessibilityPermission ? "checkmark.circle" : "lock")
                Text(
                    "割り当てたFキーの元の動作を置き換えるために必要です。Option本来の動作の無効化、音量などのシステム操作、ショートカット送信にも使用します。Fキーの割り当てとOption無効化がない通常の監視には、入力監視の権限を使用します。"
                )
                .font(.callout)
                HStack {
                    Button("アクセシビリティを許可…") { model.requestAccessibilityPermission() }
                    Button("システム設定を開く") { model.openPrivacySettings(accessibility: true) }
                    Button("状態を再確認") { model.retryMonitoring() }
                }
            }
            Section("起動と設定") {
                Toggle(
                    "ログイン時に起動",
                    isOn: Binding(
                        get: { model.loginEnabled }, set: { model.setLaunchAtLogin($0) }
                    ))
                if model.loginNeedsApproval {
                    Text("システム設定 → 一般 → ログイン項目で承認してください。")
                    Button("ログイン項目を開く") { SMAppService.openSystemSettingsLoginItems() }
                }
                Text("設定ファイル: \(model.configurationURL.path)")
                    .font(.caption).textSelection(.enabled)
                Text("パスワード入力中などのSecure Inputでは、macOSが監視を制限する場合があります。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }
}

private struct RuleEditor: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ShortcutRule
    @State private var recordingTarget: RecordingTarget?
    private enum RecordingTarget { case trigger, action }

    init(model: AppModel, rule: ShortcutRule) {
        self.model = model
        _draft = State(initialValue: rule)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("マッピングを編集").font(.title2.bold())
            Form {
                TextField("名前", text: $draft.name)
                Toggle("有効", isOn: $draft.isEnabled)
                Section("トリガー") {
                    Picker("種類", selection: triggerKind) {
                        Text("修飾キーの単独タップ").tag("modifier")
                        Text("Fキー").tag("functionKey")
                        Text("キーボードショートカット").tag("shortcut")
                    }
                    if case .modifierTap = draft.trigger {
                        Picker("物理キー", selection: modifierBinding) {
                            ForEach(PhysicalModifier.allCases) { modifier in
                                Text(modifier.title).tag(modifier)
                            }
                        }
                        Text("他のキー、クリック、ドラッグ、スクロールと併用した場合は実行しません。Caps Lockは単独タップに対応していません。")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ChordPicker(
                            combination: triggerCombination,
                            functionKeysOnly: triggerKind.wrappedValue == "functionKey"
                        )
                        Button("トリガーのキーを記録…") { beginRecording(.trigger) }
                    }
                }
                Section("アクション") {
                    Picker("種類", selection: $draft.action.kind) {
                        Text("入力ソースを切り替える").tag("inputSource")
                        Text("アプリケーションを開く").tag("launchApplication")
                        Text("URLを開く").tag("openURL")
                        Text("ショートカットを送信").tag("sendShortcut")
                        Text("音量・再生・明るさ").tag("systemAction")
                        if !["inputSource", "launchApplication", "openURL", "sendShortcut", "systemAction"]
                            .contains(
                                draft.action.kind)
                        {
                            Text("未対応: \(draft.action.kind)").tag(draft.action.kind)
                        }
                    }
                    actionFields
                }
                if let issue = model.validationMessage(for: draft.action) {
                    Label(issue, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                }
                if hasConflict {
                    Label(
                        "このトリガーは既存ルールと競合します。有効なルールが重なる間は実行されません。",
                        systemImage: "exclamationmark.triangle"
                    ).foregroundStyle(.orange)
                }
            }.formStyle(.grouped)
            if recordingTarget != nil {
                VStack(alignment: .leading, spacing: 8) {
                    Text("ショートカットを押してください（Escでキャンセル）").font(.headline)
                    ShortcutRecorder { combination in
                        if recordingTarget == .trigger {
                            draft.trigger = .keyboardShortcut(combination)
                        } else {
                            draft.action.shortcut = combination
                        }
                        endRecording()
                    } onCancel: {
                        endRecording()
                    }
                    .frame(height: 36)
                    Button("記録をキャンセル") { endRecording() }
                }.padding(10).background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
            HStack {
                Spacer()
                Button("キャンセル") {
                    endRecording(); dismiss()
                }
                .keyboardShortcut(.cancelAction)
                Button("保存") {
                    endRecording()
                    if model.saveRule(draft) { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || recordingTarget != nil)
            }
        }
        .padding(20)
        .frame(width: 640, height: recordingTarget == nil ? 620 : 740)
        .onChange(of: draft.action.kind) { kind in
            endRecording()
            if kind == "sendShortcut", draft.action.shortcut == nil {
                draft.action.shortcut = KeyCombination(keyCode: 0, modifiers: [.command])
            }
            if kind == "systemAction", draft.action.systemAction == nil {
                draft.action.systemAction = SystemAction.volumeDown.rawValue
            }
        }
        .onDisappear { endRecording() }
    }

    @ViewBuilder private var actionFields: some View {
        switch draft.action.kind {
        case "inputSource":
            Picker(
                "入力ソース",
                selection: Binding(
                    get: { draft.action.inputSourceID ?? "" },
                    set: { draft.action.inputSourceID = $0.isEmpty ? nil : $0 }
                )
            ) {
                Text("入力ソースを選択").tag("")
                ForEach(model.sources) { source in Text(source.name).tag(source.id) }
                if let id = draft.action.inputSourceID, !model.sources.contains(where: { $0.id == id }) {
                    Text("利用不可: \(id)").tag(id)
                }
            }
            Button("入力ソースを再読み込み") { model.refreshSystemState() }
            Text("表示されない場合は、システム設定 → キーボード → 入力ソースで追加してください。初期候補はこのMacのソースから選びます。")
                .font(.caption).foregroundStyle(.secondary)
        case "launchApplication":
            HStack {
                Text(draft.action.applicationPath ?? "アプリケーションを選択してください")
                    .lineLimit(2).truncationMode(.middle).font(.callout)
                Spacer()
                Button("選択…") { chooseApplication() }
            }
        case "openURL":
            TextField("URL", text: Binding(get: { draft.action.url ?? "" }, set: { draft.action.url = $0 }))
            Text("https://、http://、mailto: に対応しています。")
                .font(.caption).foregroundStyle(.secondary)
        case "sendShortcut":
            ChordPicker(combination: actionCombination)
            Button("送信するキーを記録…") { beginRecording(.action) }
            Text("アクセシビリティ権限が必要です。操作中の物理キーを離してから送信します（待機は最大5秒）。送信先はその時点の最前面アプリです。")
                .font(.caption).foregroundStyle(.secondary)
        case "systemAction":
            Picker(
                "操作",
                selection: Binding(
                    get: { draft.action.systemAction ?? "" },
                    set: { draft.action.systemAction = $0 }
                )
            ) {
                Text("操作を選択").tag("")
                ForEach(SystemAction.allCases) { action in
                    Text(action.title).tag(action.rawValue)
                }
                if let raw = draft.action.systemAction, !raw.isEmpty,
                    SystemAction(rawValue: raw) == nil
                {
                    Text("未対応: \(raw)").tag(raw)
                }
            }
            Text("アクセシビリティ権限が必要です。音量と明るさは、Fキーを長押しすると繰り返し調整できます。再生操作は対応するメディアアプリに届きます。")
                .font(.caption).foregroundStyle(.secondary)
            Text("音量や明るさをmacOSから調整できない外部スピーカー・ディスプレイでは、その機能は動作しません。")
                .font(.caption).foregroundStyle(.secondary)
        default:
            Text("このアクションは未対応です。対応する種類を選択してください。")
        }
    }

    private var hasConflict: Bool {
        let candidates = model.rules.filter { $0.id != draft.id } + [draft]
        return TriggerMatcher.conflicts(in: candidates).contains { $0.ruleIDs.contains(draft.id) }
    }

    private var triggerKind: Binding<String> {
        Binding(
            get: {
                if case .modifierTap = draft.trigger { return "modifier" }
                if case .keyboardShortcut(let combination) = draft.trigger,
                    FunctionKey.contains(combination.keyCode)
                {
                    return "functionKey"
                }
                return "shortcut"
            },
            set: { value in
                endRecording()
                switch value {
                case "modifier": draft.trigger = .modifierTap(.leftOption)
                case "functionKey": draft.trigger = .keyboardShortcut(KeyCombination(keyCode: 122))
                default:
                    draft.trigger = .keyboardShortcut(
                        KeyCombination(keyCode: 40, modifiers: [.control, .option]))
                }
            })
    }

    private var modifierBinding: Binding<PhysicalModifier> {
        Binding(
            get: {
                if case .modifierTap(let modifier) = draft.trigger { return modifier }
                return .leftOption
            }, set: { draft.trigger = .modifierTap($0) })
    }

    private var triggerCombination: Binding<KeyCombination> {
        Binding(
            get: {
                if case .keyboardShortcut(let combination) = draft.trigger { return combination }
                return KeyCombination(keyCode: 40, modifiers: [.control, .option])
            }, set: { draft.trigger = .keyboardShortcut($0) })
    }

    private var actionCombination: Binding<KeyCombination> {
        Binding(
            get: { draft.action.shortcut ?? KeyCombination(keyCode: 0, modifiers: [.command]) },
            set: { draft.action.shortcut = $0 })
    }

    private func beginRecording(_ target: RecordingTarget) {
        model.isRecording = true
        recordingTarget = target
    }

    private func endRecording() {
        recordingTarget = nil
        model.isRecording = false
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.prompt = "選択"
        if panel.runModal() == .OK { draft.action.applicationPath = panel.url?.path }
    }
}

private struct ChordPicker: View {
    @Binding var combination: KeyCombination
    var functionKeysOnly = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                modifier("⌃ Control", .control)
                modifier("⌥ Option", .option)
                modifier("⇧ Shift", .shift)
                modifier("⌘ Command", .command)
                modifier("Fn", .function)
            }
            Picker("キー", selection: $combination.keyCode) {
                ForEach(functionKeysOnly ? FunctionKey.keyCodes : KeyNames.availableKeys, id: \.self) {
                    code in
                    Text(KeyNames.name(for: code)).tag(code)
                }
            }
            Text("キーは物理位置（US配列の表記）で指定します。JIS等では刻印と異なる場合があります。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func modifier(_ title: String, _ flag: KeyModifiers) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { combination.modifiers.contains(flag) },
                set: { enabled in
                    if enabled {
                        combination.modifiers.insert(flag)
                    } else {
                        combination.modifiers.remove(flag)
                    }
                }
            )
        ).toggleStyle(.checkbox)
    }
}
