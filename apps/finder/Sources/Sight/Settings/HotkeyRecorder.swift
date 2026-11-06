import AppKit
import LaunchKit
import SwiftUI

/// A shortcut field: click it, press the keys, and it records them. Escape
/// cancels. The launcher's own shortcut is paused while it records, so
/// pressing the current one records it rather than opening the window.
struct HotkeyRecorder: NSViewRepresentable {
    let hotkey: LauncherHotkey?
    let onRecord: (LauncherHotkey) -> Void
    let onRecording: (Bool) -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.setAccessibilityIdentifier("sight.settings.general.hotkey")
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) {
        view.hotkey = hotkey
        view.onRecord = onRecord
        view.onRecording = onRecording
        view.needsDisplay = true
    }

    final class RecorderView: NSView {
        var hotkey: LauncherHotkey?
        var onRecord: ((LauncherHotkey) -> Void)?
        var onRecording: ((Bool) -> Void)?
        private(set) var recording = false {
            didSet {
                guard recording != oldValue else { return }
                onRecording?(recording)
                needsDisplay = true
                setAccessibilityValue(caption)
            }
        }

        override var intrinsicContentSize: NSSize { NSSize(width: 150, height: 24) }
        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func isAccessibilityElement() -> Bool { true }
        override func accessibilityRole() -> NSAccessibility.Role? { .button }
        override func accessibilityLabel() -> String? { "Shortcut that opens Sight" }
        override func accessibilityValue() -> Any? { caption }
        override func accessibilityPerformPress() -> Bool {
            window?.makeFirstResponder(self)
            recording = true
            return true
        }

        private var caption: String {
            if recording { return "Type the shortcut" }
            return hotkey?.display ?? "None"
        }

        override func mouseDown(with event: NSEvent) {
            window?.makeFirstResponder(self)
            recording.toggle()
        }

        override func resignFirstResponder() -> Bool {
            recording = false
            return super.resignFirstResponder()
        }

        /// Command shortcuts arrive here before keyDown.
        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording, window?.firstResponder === self else { return super.performKeyEquivalent(with: event) }
            record(event)
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard recording else {
                if event.keyCode == 49 || event.keyCode == 36 { recording = true } else { super.keyDown(with: event) }
                return
            }
            record(event)
        }

        private func record(_ event: NSEvent) {
            if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                recording = false
                return
            }
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var modifiers: UInt32 = 0
            if flags.contains(.command) { modifiers |= LauncherHotkey.command }
            if flags.contains(.shift) { modifiers |= LauncherHotkey.shift }
            if flags.contains(.option) { modifiers |= LauncherHotkey.option }
            if flags.contains(.control) { modifiers |= LauncherHotkey.control }
            let candidate = LauncherHotkey(keyCode: UInt32(event.keyCode), modifiers: modifiers)
            guard candidate.isUsable else {
                NSSound.beep()
                return
            }
            recording = false
            onRecord?(candidate)
        }

        // The system's colours, resolved for this view's appearance as it
        // draws, so the field follows Light and Dark and the accent colour.
        override func viewDidChangeEffectiveAppearance() {
            super.viewDidChangeEffectiveAppearance()
            needsDisplay = true
        }

        override func draw(_ dirtyRect: NSRect) {
            let box = bounds.insetBy(dx: 1.5, dy: 1.5)
            let path = NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6)
            NSColor.controlBackgroundColor.setFill()
            path.fill()
            NSColor.separatorColor.setStroke()
            path.lineWidth = 1
            path.stroke()
            if recording {
                // The focus ring macOS draws round a field being edited.
                let ring = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 6.5, yRadius: 6.5)
                NSColor.keyboardFocusIndicatorColor.setStroke()
                ring.lineWidth = 2.5
                ring.stroke()
            }
            let font = NSFont.preferredFont(forTextStyle: .body)
            let text = NSAttributedString(string: caption, attributes: [
                .font: font,
                .foregroundColor: recording ? NSColor.placeholderTextColor : NSColor.labelColor,
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2))
        }
    }
}
