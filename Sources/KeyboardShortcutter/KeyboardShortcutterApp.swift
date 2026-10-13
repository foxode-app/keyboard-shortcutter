import AppKit
import SwiftUI

@main
struct KeyboardShortcutterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model: AppModel

    init() {
        PreferencesMigration.migrateLegacyPreferences()
        let model = AppModel()
        _model = StateObject(wrappedValue: model)
        AppDelegate.model = model
    }

    var body: some Scene {
        MenuBarExtra {
            Text("Keyboard Shortcutter")
            Text(model.statusTitle)
            Divider()
            Button("設定を開く…") { model.showSettings() }
                .keyboardShortcut(",")
            Button(model.isPaused ? "監視を再開" : "監視を一時停止") { model.togglePaused() }
            Toggle(
                "ログイン時に起動",
                isOn: Binding(
                    get: { model.loginEnabled }, set: { model.setLaunchAtLogin($0) }
                ))
            if model.loginNeedsApproval {
                Text("ログイン項目の承認が必要です")
            }
            if model.errorMessage != nil { Text("設定画面にエラーがあります") }
            Divider()
            Link(FoxodeWebsite.title, destination: FoxodeWebsite.productURL)
            Divider()
            Button("Keyboard Shortcutterを終了") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: model.isMonitoring ? "keyboard" : "keyboard.badge.ellipsis")
                .accessibilityLabel("Keyboard Shortcutter: \(model.statusTitle)")
        }
        .menuBarExtraStyle(.menu)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Self.model?.start()
    }

    func applicationWillTerminate(_ notification: Notification) { Self.model?.stop() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Self.model?.showSettings()
        return true
    }
}
