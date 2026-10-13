import SwiftUI

#if canImport(ShortcutCore)
import ShortcutCore
#endif

struct FunctionKeySettingsView: View {
    @ObservedObject var model: AppModel
    let onEdit: (ShortcutRule) -> Void
    let onDelete: (ShortcutRule) -> Void
    let actionSummary: (ShortcutAction) -> String

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Fキーを、自分の使い方に。")
                        .font(.headline)
                    Text("キーを選び、音量・再生・明るさ、アプリ起動、URL、キーの組み合わせなどを割り当てます。Controlなどとの組み合わせも登録できます。")
                        .font(.callout).foregroundStyle(.secondary)
                    Button("F9：音量− ／ F10：音量＋を追加") { addVolumePreset() }
                        .disabled(!model.configurationAvailable || volumeKeysHaveRules)
                    if volumeKeysHaveRules {
                        Text("F9またはF10は登録済みです。各キーの「編集」で変更できます。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                if model.hasFunctionKeyMappings {
                    HStack(alignment: .top) {
                        Label(
                            model.isFunctionKeySuppressionActive ? "Fキーの割り当てが動作中" : "Fキーの割り当ては停止中",
                            systemImage: model.isFunctionKeySuppressionActive
                                ? "checkmark.circle" : "pause.circle"
                        ).foregroundStyle(model.isFunctionKeySuppressionActive ? .green : .secondary)
                        Spacer()
                        if !model.hasAccessibilityPermission {
                            Button("アクセシビリティを許可…") { model.requestAccessibilityPermission() }
                        } else if !model.isPaused && !model.isMonitoring {
                            Button("監視を再開") { model.retryMonitoring() }
                        }
                    }.font(.callout)
                    if !model.isFunctionKeySuppressionActive {
                        Text(model.status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 310), alignment: .top)], spacing: 12) {
                    ForEach(FunctionKey.keyCodes, id: \.self) { code in
                        keyCard(code)
                    }
                }
                Text(
                    "Fキーが音量や再生キーとして動く場合は、macOSの「キーボード → キーボードショートカット → ファンクションキー」で標準のFキーとして使う設定を確認してください。外付けキーボードではFnロックなどの設定が必要な場合があります。Fnと併用する場合は、その組み合わせを登録してください。"
                )
                .font(.caption).foregroundStyle(.secondary)
                Text("割り当てのないキーは通常どおり使えます。一時停止・終了すると割り当てを停止します。F13〜F20は、対応するキーがあるキーボードで使用できます。")
                    .font(.caption).foregroundStyle(.secondary)
            }.padding(16)
        }
    }

    private func keyCard(_ code: UInt16) -> some View {
        let rules = rules(for: code)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(KeyNames.name(for: code)).font(.headline.monospaced())
                Spacer()
                Button(rules.isEmpty ? "割り当てる…" : "追加…") {
                    onEdit(
                        ShortcutRule(
                            name: "\(KeyNames.name(for: code))の操作",
                            trigger: .keyboardShortcut(KeyCombination(keyCode: code)),
                            action: ShortcutAction(
                                kind: "systemAction", systemAction: SystemAction.volumeDown.rawValue)
                        ))
                }.disabled(!model.configurationAvailable)
            }
            if rules.isEmpty {
                Text("未設定・通常の動作").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(rules) { rule in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(rule.trigger.title) → \(actionSummary(rule.action))")
                            .font(.callout).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Toggle(
                                "有効",
                                isOn: Binding(get: { rule.isEnabled }, set: { _ in model.toggleRule(rule) })
                            ).toggleStyle(.checkbox)
                                .accessibilityLabel("\(rule.name)を有効にする")
                            Spacer()
                            Button("編集") { onEdit(rule) }
                            Button {
                                onDelete(rule)
                            } label: {
                                Image(systemName: "trash")
                            }.help("\(rule.name)を削除")
                        }
                        if let conflict = model.conflicts.first(where: { $0.ruleIDs.contains(rule.id) }) {
                            Label(conflict.message, systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        } else if let issue = model.validationMessage(for: rule.action) {
                            Label(issue, systemImage: "exclamationmark.circle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }.disabled(!model.configurationAvailable)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func rules(for code: UInt16) -> [ShortcutRule] {
        model.rules.filter {
            if case .keyboardShortcut(let combination) = $0.trigger {
                return combination.keyCode == code
            }
            return false
        }
    }

    private var volumeKeysHaveRules: Bool {
        model.rules.contains {
            if case .keyboardShortcut(let combination) = $0.trigger {
                return [101, 109].contains(combination.keyCode) && combination.modifiers.isEmpty
            }
            return false
        }
    }

    private func addVolumePreset() {
        guard !volumeKeysHaveRules else { return }
        _ = model.saveRules([
            ShortcutRule(
                name: "F9で音量を下げる", trigger: .keyboardShortcut(KeyCombination(keyCode: 101)),
                action: ShortcutAction(kind: "systemAction", systemAction: SystemAction.volumeDown.rawValue)),
            ShortcutRule(
                name: "F10で音量を上げる", trigger: .keyboardShortcut(KeyCombination(keyCode: 109)),
                action: ShortcutAction(kind: "systemAction", systemAction: SystemAction.volumeUp.rawValue)),
        ])
    }
}
