import AppKit
import BrowserKit
import FileKit
import ThemeKit

/// Nexus's Settings, read once from its defaults domain and applied to every
/// open window as they change, so nothing needs a restart.
@MainActor
final class NexusPreferencesStore: ObservableObject {
    static let shared = NexusPreferencesStore()

    @Published private(set) var current: NexusPreferences
    /// Row density from Settings, Appearance (or the theme's UI_DENSITY).
    @Published private(set) var density: Density
    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        current = NexusPreferences(defaults: defaults)
        density = Density.current(theme: nil, defaults: defaults)
    }

    /// Changes, saves and applies.
    func update(_ change: (inout NexusPreferences) -> Void) {
        var next = current
        change(&next)
        guard next != current else { return }
        let old = current
        current = next
        next.save(to: defaults)
        apply(old: old, new: next)
    }

    func densityChanged(_ value: Density) {
        density = value
        Services.shared.objectWillChange.send()
    }

    /// The list row height for the density in use.
    func rowHeight(theme: Theme?) -> CGFloat {
        CGFloat((theme?.density ?? density).scaled(Double(FileTableSetup.rowHeight)))
    }

    private func apply(old: NexusPreferences, new: NexusPreferences) {
        let models = WindowManager.shared.models
        if old.showPathBar != new.showPathBar {
            for model in models { model.showPathBar = new.showPathBar }
        }
        if old.showStatusBar != new.showStatusBar {
            for model in models { model.showStatusBar = new.showStatusBar }
        }
        if old.openFoldersInTabs != new.openFoldersInTabs {
            for model in models { model.window?.tabbingMode = Self.tabbingMode(new) }
        }
        if old.sidebar != new.sidebar {
            Services.shared.sidebar.refresh()
        }
        if old.showKindColours != new.showKindColours || old.showAllExtensions != new.showAllExtensions {
            Services.shared.objectWillChange.send()
            for model in models { model.objectWillChange.send() }
        }
    }

    static func tabbingMode(_ prefs: NexusPreferences) -> NSWindow.TabbingMode {
        prefs.openFoldersInTabs ? .preferred : .automatic
    }

    /// Where a new window opens (Cmd+N, launch, the Dock icon).
    func newWindowLocation(current folder: URL?) -> BrowserLocation {
        let home = Services.shared.paths.home
        return current.newWindowTarget.location(current: folder, home: home, drives: GoogleDrive.accounts(home: home))
    }
}
