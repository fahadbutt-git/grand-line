import AppKit

/// Den Den, the notch app of Grand Line. It has no Dock icon (LSUIElement):
/// its menu bar item, or a right-click on the notch, has its menu and Settings.
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
