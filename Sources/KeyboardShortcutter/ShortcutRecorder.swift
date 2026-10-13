import AppKit
import SwiftUI

#if canImport(ShortcutCore)
import ShortcutCore
#endif

/// Receives only events delivered to this focused view; it never stores text or monitors globally.
struct ShortcutRecorder: NSViewRepresentable {
    let onRecord: (KeyCombination) -> Void
    let onCancel: () -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.onRecord = onRecord
        view.onCancel = onCancel
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.onRecord = onRecord
        view.onCancel = onCancel
    }

    final class RecorderView: NSView {
        var onRecord: ((KeyCombination) -> Void)?
        var onCancel: (() -> Void)?
        private var finished = false
        private var functionIsDown = false
        override var acceptsFirstResponder: Bool { true }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                functionIsDown = CGEventSource.keyState(.hidSystemState, key: 63)
                window.makeFirstResponder(self)
                setAccessibilityLabel("ショートカット記録。キーを押してください。Escapeでキャンセル。")
            }
        }

        override func draw(_ dirtyRect: NSRect) {
            NSColor.controlAccentColor.withAlphaComponent(0.12).setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
            let text = "キー入力を待っています…" as NSString
            text.draw(
                at: NSPoint(x: 10, y: 9),
                withAttributes: [
                    .font: NSFont.systemFont(ofSize: 13), .foregroundColor: NSColor.labelColor,
                ])
        }

        override func keyDown(with event: NSEvent) { capture(event) }

        override func flagsChanged(with event: NSEvent) {
            // Arrow and F-key events also carry .function; only key 63 changes physical Fn state.
            if event.keyCode == 63 { functionIsDown = event.modifierFlags.contains(.function) }
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard window?.firstResponder === self, event.type == .keyDown else { return false }
            capture(event)
            return true
        }

        override func resignFirstResponder() -> Bool {
            if !finished {
                finished = true
                DispatchQueue.main.async { [weak self] in self?.onCancel?() }
            }
            return true
        }

        private func capture(_ event: NSEvent) {
            guard !finished, !event.isARepeat else { return }
            if event.keyCode == 53 {
                finished = true
                onCancel?()
                return
            }
            var modifiers: KeyModifiers = []
            if event.modifierFlags.contains(.control) { modifiers.insert(.control) }
            if event.modifierFlags.contains(.option) { modifiers.insert(.option) }
            if event.modifierFlags.contains(.shift) { modifiers.insert(.shift) }
            if event.modifierFlags.contains(.command) { modifiers.insert(.command) }
            if functionIsDown { modifiers.insert(.function) }
            let combination = KeyCombination(keyCode: event.keyCode, modifiers: modifiers)
            guard combination.isValid else { return }
            finished = true
            onRecord?(combination)
        }
    }
}
