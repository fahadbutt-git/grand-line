import Foundation

/// The main menu (Caps + Option + Space) as rows: "Toggle › Dark mode", ticked
/// when on. Guards and checks run in the background whenever the window opens.
public final class MenuProvider: InstantProvider, @unchecked Sendable {
    public let id = "menu"
    public let title = "Grand Line menu"
    public let symbol = "menubar.rectangle"
    public let prefix: Prefix? = nil
    public let extraPrefixes: [Prefix] = [.shell]
    public let inGlobalSearch = true
    let paths: GrandLinePaths
    let runner: ShellRunner
    let catalog = Catalog()

    public init(paths: GrandLinePaths = GrandLinePaths(), runner: ShellRunner = ShellRunner()) {
        self.paths = paths
        self.runner = runner
    }

    public static func results(_ entries: [MenuEntry], states: [MenuStateProbe.State]?) -> [LaunchResult] {
        entries.enumerated().compactMap { i, entry in
            let state = states.map { $0[i] } ?? MenuStateProbe.State(shown: entry.guardTest == nil, checked: false)
            guard state.shown else { return nil }
            return LaunchResult(
                id: "menu:" + entry.path,
                title: entry.label,
                subtitle: entry.groups.joined(separator: " › "),
                icon: .symbol(symbol(for: entry.groups.first ?? "")),
                section: .grandLine,
                keywords: entry.groups + [entry.path],
                accessory: state.checked ? "On" : "",
                actions: [
                    // Restart, shut down, log out and sleep ask first, here as in Settings rows.
                    LaunchAction("Run", symbol: "play", confirmation: entry.confirmation, .shell(entry.command)),
                    LaunchAction.copy(entry.command, title: "Copy command"),
                    .favourite,
                ],
                providerID: "menu"
            )
        }
    }

    static func symbol(for group: String) -> String {
        switch group.lowercased() {
        case "toggle": return "switch.2"
        case "capture": return "camera.viewfinder"
        case "transcode": return "arrow.triangle.2.circlepath"
        case "style": return "paintpalette"
        case "install", "remove": return "shippingbox"
        case "files": return "folder"
        case "system": return "power"
        case "learn": return "keyboard"
        case "settings": return "gearshape"
        default: return "menubar.rectangle"
        }
    }

    /// Reads the menu files; then, if any entry has a guard or check, runs them and reads again.
    public func reload() async {
        let entries = MenuFile.load(paths)
        catalog.replace(Self.results(entries, states: nil))
        guard MenuStateProbe.needsProbe(entries) else { return }
        let script = MenuStateProbe.script(for: entries, helpers: paths.toggleState)
        guard let output = try? await runner.run("/bin/bash", ["-c", script], timeout: 5) else { return }
        catalog.replace(Self.results(entries, states: MenuStateProbe.parse(output.stdout, entries: entries)))
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        guard !query.term.isEmpty else { return [] }
        return catalog.search(query.term, exactOnly: query.prefix == .exact, limit: 40)
    }

    // MARK: Rows the settings rows already offer

    /// The settings row ("setting.darkmode") a menu row (or a shortcut's row)
    /// duplicates: one that runs the same bin/toggle setting, bin/power action
    /// or capture, whatever else its line says ("toggle dark" and "toggle dark
    /// on" are both dark mode).
    public static func settingDuplicated(by row: LaunchResult) -> String? {
        guard row.providerID == "menu" || row.providerID == "keybindings", case .shell(let line)? = row.primary?.command else { return nil }
        let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard words.count >= 2 else { return nil }
        let command = (words[0] as NSString).lastPathComponent
        for setting in SettingsActions.toggles + SettingsActions.actions {
            switch setting.kind {
            case .toggle(let name, _, _) where command == "toggle" && words[1] == name:
                return setting.id
            case .power(let what, _) where command == "power" && words[1] == what:
                return setting.id
            case .capture(let what) where command == "capture" && words[1] == what:
                return setting.id
            default:
                continue
            }
        }
        return nil
    }

    /// Drops menu rows whose setting is already among the results as a
    /// settings row ("dark mode" shows the Dark mode settings row, with its
    /// state and its accessibility id, not the menu's Toggle › Dark mode too).
    /// Menu rows stay when no settings row answers (the settings source is
    /// off, or the words match only the menu).
    public static func withoutSettingDuplicates(_ results: [LaunchResult]) -> [LaunchResult] {
        let settings = Set(results.lazy.filter { $0.providerID == SettingsActionsProvider.providerID }.map(\.id))
        guard !settings.isEmpty else { return results }
        return results.filter { row in
            guard let duplicated = settingDuplicated(by: row) else { return true }
            return !settings.contains(duplicated)
        }
    }
}
