import AppKit

/// Den Den, the notch app of Grand Line. It has no Dock icon and no menu bar
/// item (LSUIElement): right-click the notch for its menu.
@main
enum DenDenApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}
