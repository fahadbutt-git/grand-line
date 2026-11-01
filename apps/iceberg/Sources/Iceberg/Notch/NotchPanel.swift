import AppKit
import SwiftUI

/// A borderless panel above the menu bar on every Space, never key and never
/// in the window cycle, as Boring Notch and DynamicNotchKit set theirs up.
final class NotchPanel: NSPanel {
    override init(contentRect: NSRect, styleMask: NSWindow.StyleMask, backing: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        isFloatingPanel = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        isReleasedWhenClosed = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        animationBehavior = .none
    }

    static func make() -> NotchPanel {
        NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Holds the SwiftUI view and reports the pointer entering and leaving the
/// panel, with a tracking area that works while Iceberg is in the background.
final class HoverContainerView: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        let a = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(a)
        area = a
    }

    override func mouseEntered(with event: NSEvent) { onEnter?() }
    override func mouseExited(with event: NSEvent) { onExit?() }

    /// Files dropped on the panel (the shelf), when it takes them.
    let drops = FileDropTarget()
    private var takesFiles = false

    /// Registers for dropped files while the shelf is on, and not otherwise.
    func setTakesFiles(_ on: Bool) {
        guard on != takesFiles else { return }
        takesFiles = on
        if on { registerForDraggedTypes([.fileURL]) } else { unregisterDraggedTypes() }
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { drops.entered(sender) }
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        MainActor.assumeIsolated { drops.entered(sender) }
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        MainActor.assumeIsolated { drops.exited() }
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { true }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        MainActor.assumeIsolated { drops.perform(sender) }
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        MainActor.assumeIsolated { drops.exited() }
    }

    /// True when the pointer is inside right now (after a resize). The top
    /// edge counts: a pointer pushed against the notch sits on it.
    var containsPointer: Bool {
        guard let frame = window?.frame else { return false }
        let p = NSEvent.mouseLocation
        return p.x >= frame.minX && p.x <= frame.maxX && p.y >= frame.minY && p.y <= frame.maxY
    }
}

/// Lets the first click act at once, though the panel is never key.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
