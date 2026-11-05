import AppKit
import Combine
import IcebergKit

/// System Settings, Accessibility, Display: Reduce Motion, Reduce
/// Transparency and Increase Contrast, kept current as they change.
/// Read through `shared` by every surface that draws differently for them.
@MainActor
final class DisplayOptions: ObservableObject {
    static let shared = DisplayOptions()

    @Published private(set) var reduceMotion: Bool
    @Published private(set) var reduceTransparency: Bool
    @Published private(set) var increaseContrast: Bool
    private var observer: NSObjectProtocol?

    private init() {
        let w = NSWorkspace.shared
        reduceMotion = w.accessibilityDisplayShouldReduceMotion
        reduceTransparency = w.accessibilityDisplayShouldReduceTransparency
        increaseContrast = w.accessibilityDisplayShouldIncreaseContrast
        observer = w.notificationCenter.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
                                                    object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func refresh() {
        let w = NSWorkspace.shared
        if w.accessibilityDisplayShouldReduceMotion != reduceMotion { reduceMotion = w.accessibilityDisplayShouldReduceMotion }
        if w.accessibilityDisplayShouldReduceTransparency != reduceTransparency {
            reduceTransparency = w.accessibilityDisplayShouldReduceTransparency
        }
        if w.accessibilityDisplayShouldIncreaseContrast != increaseContrast {
            increaseContrast = w.accessibilityDisplayShouldIncreaseContrast
        }
    }

    /// How the floating surfaces are drawn now.
    var surface: SurfaceStyle {
        SurfaceStyle.resolve(reduceTransparency: reduceTransparency, increaseContrast: increaseContrast)
    }
}
