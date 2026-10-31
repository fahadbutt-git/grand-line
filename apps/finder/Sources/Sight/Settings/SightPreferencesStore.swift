import AppKit
import LaunchKit
import LauncherKit
import ServiceManagement
import ThemeKit

/// Sight's Settings, read from its defaults domain (com.grandline.sight) and
/// handed to the search services, the menu bar item and the shortcut as they
/// change, so nothing needs a restart.
@MainActor
final class SightPreferencesStore: ObservableObject {
    @Published private(set) var current: SightPreferences
    @Published private(set) var hotkey: LauncherHotkey?
    /// Why the shortcut could not be registered, if it could not.
    @Published var hotkeyProblem: String?
    @Published private(set) var density: Density

    let defaults: UserDefaults
    private let services: Services
    /// Set by the app delegate: register the shortcut again, show or hide the
    /// menu bar item, pause the shortcut while a new one is recorded.
    var onHotkeyChange: ((LauncherHotkey?) -> Bool)?
    var onMenuBarIconChange: ((Bool) -> Void)?
    var onRecording: ((Bool) -> Void)?
    var onDensityChange: (() -> Void)?

    init(services: Services, defaults: UserDefaults = .standard) {
        self.services = services
        self.defaults = defaults
        current = services.preferences
        hotkey = HotkeySetting.hotkey(defaults)
        density = Density.current(theme: nil, defaults: defaults)
    }

    func update(_ change: (inout SightPreferences) -> Void) {
        var next = current
        change(&next)
        guard next != current else { return }
        let old = current
        current = next
        next.save(to: defaults)
        services.apply(next)
        if old.showMenuBarIcon != next.showMenuBarIcon { onMenuBarIconChange?(next.showMenuBarIcon) }
        if old.launchAtLogin != next.launchAtLogin { Self.setLaunchAtLogin(next.launchAtLogin) }
    }

    // MARK: The shortcut

    /// nil goes back to Command+Space (when setup handed it over).
    func setHotkey(_ new: LauncherHotkey?) {
        HotkeySetting.setHotkey(new, defaults)
        hotkey = HotkeySetting.hotkey(defaults)
        let registered = onHotkeyChange?(hotkey) ?? true
        if let hotkey, !registered {
            hotkeyProblem = "\(hotkey.display) is taken by macOS or another app. Choose another shortcut."
        } else {
            hotkeyProblem = nil
        }
    }

    var takesCommandSpace: Bool { HotkeySetting.takesCommandSpace(defaults) }

    // MARK: Login

    static var opensAtLogin: Bool { SMAppService.mainApp.status == .enabled }

    static func setLaunchAtLogin(_ on: Bool) {
        // A test run starts a temporary copy that must not become a login item.
        guard ProcessInfo.processInfo.environment["GRAND_LINE_JOURNEY"] != "1" else { return }
        if on {
            if SMAppService.mainApp.status != .enabled { try? SMAppService.mainApp.register() }
        } else if SMAppService.mainApp.status == .enabled {
            try? SMAppService.mainApp.unregister()
        }
    }

    // MARK: Density

    func densityChanged(_ value: Density) {
        density = value
        onDensityChange?()
    }

    // MARK: Advanced

    /// Moves usage.json to the Trash (never deletes it) and forgets what was learned.
    func resetUsage() -> String {
        let file = URL(fileURLWithPath: services.paths.usage)
        if FileManager.default.fileExists(atPath: file.path) {
            do {
                try FileManager.default.trashItem(at: file, resultingItemURL: nil)
            } catch {
                return "The history could not be moved to the Trash: \(error.localizedDescription)"
            }
        }
        services.usage.reset()
        return "History moved to the Trash. Rankings start fresh."
    }

    func reloadSources() {
        services.reloadSources(force: true)
    }
}
