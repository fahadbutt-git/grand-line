import AppKit

// Byakugan lives in the menu bar (LSUIElement) and keeps its window and index
// in memory, so Command+Space shows results at once.
MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
