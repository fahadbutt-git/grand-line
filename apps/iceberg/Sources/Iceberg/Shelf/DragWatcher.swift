import AppKit
import IcebergKit

/// Notices a file being dragged in any app, so the notch can open to take
/// it (the shelf) and a shake can bring up the drop basket.
///
/// Global monitors for the left button (down, dragged, up) are installed
/// only while the shelf or the basket is turned on. Nothing runs between
/// events: no timer, no polling. While a drag carries no files, each event
/// is a few comparisons (`DragSessionTracker`); only during a file drag do
/// the dragged events feed the shake detector.
@MainActor
final class DragWatcher {
    private var tracker = DragSessionTracker()
    private var shake = ShakeDetector()
    private var monitors: [Any] = []
    private let pasteboard = NSPasteboard(name: .drag)

    /// Listen for shakes (`drag_basket`).
    var shakeEnabled = false
    /// A shake during a file drag, with the pointer's position.
    var onShake: ((CGPoint) -> Void)?
    /// A file drag ended.
    var onEnded: (() -> Void)?

    var isFileDrag: Bool { tracker.isFileDrag }

    func setActive(_ on: Bool) {
        if on == !monitors.isEmpty { return }
        if !on {
            for m in monitors { NSEvent.removeMonitor(m) }
            monitors = []
            tracker = DragSessionTracker()
            return
        }
        let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseDown() }
        }
        let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            let time = event.timestamp
            MainActor.assumeIsolated { self?.mouseDragged(at: time) }
        }
        let up = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseUp() }
        }
        monitors = [down, dragged, up].compactMap { $0 }
    }

    private func mouseDown() {
        if tracker.mouseDown(changeCount: pasteboard.changeCount) == .ended { onEnded?() }
    }

    private func mouseDragged(at time: TimeInterval) {
        let pb = pasteboard
        switch tracker.dragged(changeCount: { pb.changeCount }, hasFiles: { FileDragPasteboard.hasFiles(pb) }) {
        case .began:
            shake.reset()
            feedShake(at: time)
        case .moved:
            feedShake(at: time)
        case .none, .ended:
            break
        }
    }

    private func feedShake(at time: TimeInterval) {
        guard shakeEnabled else { return }
        let p = NSEvent.mouseLocation
        if shake.add(x: Double(p.x), at: time) { onShake?(p) }
    }

    private func mouseUp() {
        if tracker.mouseUp() == .ended { onEnded?() }
    }
}
