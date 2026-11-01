import Foundation
import IndexKit

/// Settings changed from the search field: "dark mode", "wifi off", "volume 30",
/// "hidden files", "bt off". Each row does the change on Return and shows the
/// state it found; Command+Return opens its System Settings pane instead.
///
/// The changes are bin/toggle and bin/power, the same commands the main menu
/// runs, called with an argument list (never a shell line). The state comes
/// from `toggle status`, read when the window opens and again after each change.
public enum SettingsActions {
    /// A permission macOS asks for before a change can be made.
    public enum Permission: String, Sendable, Equatable {
        case automation
        case accessibility

        public var title: String {
            switch self {
            case .automation: return "Automation"
            case .accessibility: return "Accessibility"
            }
        }

        /// Privacy & Security, scrolled to this permission.
        public var paneURL: String {
            switch self {
            case .automation: return "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
            case .accessibility: return "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
            }
        }
    }

    /// One phrase that names a setting. `implies` is the state the phrase asks
    /// for by itself: "light mode" is dark mode off, "show hidden files" is on.
    /// `opposite` names the thing the setting takes away, so on and off after
    /// it mean the other way round: "microphone on" is Mute microphone off,
    /// "dock on" is Dock autohide off. Alone, such a phrase switches the setting.
    public struct Name: Sendable, Equatable {
        public let phrase: String
        public let implies: Bool?
        public let opposite: Bool

        public init(_ phrase: String, implies: Bool? = nil, opposite: Bool = false) {
            self.phrase = phrase
            self.implies = implies
            self.opposite = opposite
        }
    }

    public enum Kind: Sendable, Equatable {
        /// A bin/toggle setting. `inverted` when its on is the toggle's off
        /// (Dock autohide on is `toggle dock off`, the Dock no longer always shown).
        case toggle(name: String, stateKey: String, inverted: Bool)
        /// A bin/power action; `confirm` asks before running it.
        case power(String, confirm: String?)
        /// A bin/capture action. It is interactive, so it runs without waiting.
        case capture(String)
        /// No command can make this change, so Return opens its pane and the row says why.
        case paneOnly(reason: String)
    }

    public struct Setting: Sendable, Equatable {
        /// The row id's last part, "darkmode" in "setting.darkmode".
        public let key: String
        public let title: String
        public let symbol: String
        public let names: [Name]
        public let kind: Kind
        /// The System Settings pane (by its title in SettingsPanes) Command+Return opens.
        public let pane: String?
        /// The permission to suggest when the change does not take.
        public let permission: Permission?
        public let timeout: TimeInterval

        public var id: String { "setting." + key }

        init(_ key: String, _ title: String, symbol: String, names: [Name], kind: Kind, pane: String?, permission: Permission? = nil, timeout: TimeInterval = 8) {
            self.key = key
            self.title = title
            self.symbol = symbol
            self.names = names
            self.kind = kind
            self.pane = pane
            self.permission = permission
            self.timeout = timeout
        }
    }

    // MARK: The settings

    static func n(_ phrases: String..., implies: Bool? = nil) -> [Name] {
        phrases.map { Name($0, implies: implies) }
    }

    /// Names of what the setting takes away: "mic" for Mute microphone.
    static func opposite(_ phrases: String...) -> [Name] {
        phrases.map { Name($0, opposite: true) }
    }

    public static let toggles: [Setting] = [
        Setting("darkmode", "Dark mode", symbol: "circle.lefthalf.filled",
                names: n("dark mode", "dark", "dark theme", "dark appearance", "night theme") + n("light mode", "light", "light theme", "light appearance", implies: false),
                kind: .toggle(name: "dark", stateKey: "dark", inverted: false), pane: "Appearance",
                permission: .automation, timeout: 30),
        Setting("wifi", "Wi-Fi", symbol: "wifi",
                names: n("wifi", "wireless", "airport", "wlan"),
                kind: .toggle(name: "wifi", stateKey: "wifi", inverted: false), pane: "Wi-Fi"),
        Setting("bluetooth", "Bluetooth", symbol: "dot.radiowaves.left.and.right",
                names: n("bluetooth", "bt", "blue tooth"),
                kind: .toggle(name: "bluetooth", stateKey: "bluetooth", inverted: false), pane: "Bluetooth"),
        Setting("dnd", "Do Not Disturb", symbol: "moon",
                names: n("do not disturb", "dnd", "focus", "focus mode", "dont disturb", "quiet mode"),
                kind: .toggle(name: "dnd", stateKey: "dnd", inverted: false), pane: "Focus", timeout: 15),
        Setting("mute", "Mute sound", symbol: "speaker.slash",
                names: n("mute", "mute sound", "sound mute", "mute audio", "muted") + n("unmute", "unmute sound", implies: false),
                kind: .toggle(name: "mute", stateKey: "mute", inverted: false), pane: "Sound"),
        Setting("micmute", "Mute microphone", symbol: "mic.slash",
                names: n("mute mic", "mute microphone", "mic mute", "microphone mute", "mic muted", "microphone muted") + opposite("mic", "microphone")
                    + n("unmute mic", "unmute microphone", implies: false),
                kind: .toggle(name: "mic", stateKey: "mic-muted", inverted: false), pane: "Sound"),
        Setting("hiddenfiles", "Show hidden files", symbol: "eye",
                names: n("hidden files", "hidden", "dotfiles", "dot files", "invisible files") + n("show hidden files", "show hidden", "show dotfiles", "show all files", implies: true)
                    + n("hide hidden files", "hide dotfiles", implies: false),
                kind: .toggle(name: "hidden", stateKey: "hidden", inverted: false), pane: nil),
        Setting("dockautohide", "Dock autohide", symbol: "dock.rectangle",
                names: n("dock autohide", "autohide dock", "dock hiding") + opposite("dock") + n("hide dock", "hide the dock", implies: true)
                    + n("show dock", "dock always shown", implies: false),
                kind: .toggle(name: "dock", stateKey: "dock", inverted: true), pane: "Desktop & Dock"),
        Setting("desktopicons", "Desktop icons", symbol: "menubar.dock.rectangle",
                names: n("desktop icons", "icons on desktop", "desktop items") + n("show desktop icons", implies: true) + n("hide desktop icons", "clean desktop", implies: false),
                kind: .toggle(name: "desktop-icons", stateKey: "desktop-icons", inverted: false), pane: "Desktop & Dock"),
        Setting("menubarautohide", "Menu bar autohide", symbol: "menubar.rectangle",
                names: n("menu bar autohide", "autohide menu bar", "menubar autohide") + opposite("menu bar", "menubar") + n("hide menu bar", "hide menubar", implies: true)
                    + n("show menu bar", "show menubar", implies: false),
                kind: .toggle(name: "menubar", stateKey: "menubar", inverted: true), pane: "Control Center",
                permission: .automation),
        Setting("keepawake", "Keep awake", symbol: "cup.and.saucer",
                names: n("keep awake", "awake", "caffeinate", "caffeine", "stay awake", "keep mac awake", "no sleep", "prevent sleep", "amphetamine"),
                kind: .toggle(name: "awake", stateKey: "awake", inverted: false), pane: "Battery"),
    ]

    public static let actions: [Setting] = [
        Setting("lock", "Lock screen", symbol: "lock",
                names: n("lock", "lock screen", "lock mac", "lock computer", "lock the screen"),
                kind: .power("lock", confirm: nil), pane: "Lock Screen", permission: .accessibility),
        Setting("displaysleep", "Sleep display", symbol: "display",
                names: n("sleep display", "display sleep", "display off", "off display", "screen off", "off screen", "sleep screen", "monitor off"),
                kind: .power("display-sleep", confirm: nil), pane: "Lock Screen"),
        Setting("sleep", "Sleep", symbol: "moon.zzz",
                names: n("sleep", "sleep mac", "go to sleep", "sleep computer", "sleep now"),
                kind: .power("sleep", confirm: "Press Return again to put the Mac to sleep"), pane: "Lock Screen"),
        Setting("logout", "Log out", symbol: "rectangle.portrait.and.arrow.right",
                names: n("log out", "logout", "sign out", "log off"),
                kind: .power("logout", confirm: "Press Return again to log out"), pane: nil,
                permission: .automation, timeout: 30),
        Setting("restart", "Restart", symbol: "restart",
                names: n("restart", "reboot", "restart mac", "restart computer"),
                kind: .power("restart", confirm: "Press Return again to restart"), pane: nil,
                permission: .automation, timeout: 30),
        Setting("shutdown", "Shut down", symbol: "power",
                names: n("shut down", "shutdown", "power off", "off mac", "off computer", "power down"),
                kind: .power("shutdown", confirm: "Press Return again to shut down"), pane: nil,
                permission: .automation, timeout: 30),
        Setting("screenshot.area", "Screenshot of an area", symbol: "camera.viewfinder",
                names: n("screenshot", "screen shot", "screenshot area", "capture area", "screen capture", "snip"),
                kind: .capture("area"), pane: nil),
        Setting("screenshot.window", "Screenshot of a window", symbol: "macwindow",
                names: n("screenshot window", "window screenshot", "capture window"),
                kind: .capture("window"), pane: nil),
        Setting("screenshot.screen", "Screenshot of the whole screen", symbol: "rectangle.dashed",
                names: n("screenshot screen", "screenshot full screen", "screenshot whole screen", "full screenshot", "capture screen"),
                kind: .capture("screen"), pane: nil),
        Setting("screenrecording", "Record the screen", symbol: "record.circle",
                names: n("record screen", "screen recording", "screen record", "start recording", "record"),
                kind: .capture("record"), pane: nil),
        Setting("screentext", "Copy text from a screen area", symbol: "text.viewfinder",
                names: n("copy text from screen", "screen text", "capture text", "ocr", "text from screen"),
                kind: .capture("text"), pane: nil),
        Setting("nightshift", "Night Shift", symbol: "sun.max",
                names: n("night shift", "nightshift", "night light", "warm screen", "blue light"),
                kind: .paneOnly(reason: "macOS has no command for Night Shift. Return opens Displays"), pane: "Displays"),
        Setting("lowpower", "Low Power Mode", symbol: "battery.25",
                names: n("low power", "low power mode", "battery saver", "power saving", "energy saver"),
                kind: .paneOnly(reason: "Changing it needs an administrator password. Return opens Battery"), pane: "Battery"),
        Setting("brightness", "Brightness", symbol: "sun.min",
                names: n("brightness", "brighter", "dimmer", "screen brightness", "dim screen"),
                kind: .paneOnly(reason: "No brightness command is installed. Return opens Displays"), pane: "Displays"),
    ]

    /// Every setting, by key.
    public static let byKey: [String: Setting] = Dictionary((toggles + actions).map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })

    // MARK: Reading the query

    /// What a query asks for.
    public enum Request: Sendable, Equatable {
        /// A toggle, set to a state or (nil) flipped.
        case toggle(key: String, desired: Bool?)
        case action(key: String)
        case volumeSet(Int)
        case volumeUp
        case volumeDown
    }

    public struct Match: Sendable, Equatable {
        public let request: Request
        /// The whole phrase was a name; otherwise it was the start of one, still being typed.
        public let exact: Bool
        /// Breaks ties between rows from the same query; higher first.
        public let order: Int
    }

    static let fillers: Set<String> = ["turn", "switch", "set", "toggle", "please", "the", "to", "my", "now"]
    static let onWords: Set<String> = ["on", "enable", "enabled", "activate", "start"]
    static let offWords: Set<String> = ["off", "disable", "disabled", "deactivate", "stop"]

    /// Lowercase words without accents; "Wi-Fi" is "wifi", "30%" is "30".
    public static func words(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).lowercased()
        var cleaned = ""
        for ch in folded {
            if ch == "-" || ch == "_" || ch == "%" || ch == "'" || ch == "’" { continue }
            cleaned.append(ch.isLetter || ch.isNumber ? ch : " ")
        }
        return cleaned.split(separator: " ").map(String.init)
    }

    /// Every setting a query asks for, best first.
    public static func parse(_ text: String) -> [Match] {
        let kept = words(text).filter { !fillers.contains($0) }
        guard !kept.isEmpty else { return [] }
        var found: [Match] = []
        found += volume(kept)
        found += phraseActions(kept)
        found += toggleRequests(kept)
        // One row per setting: the exact reading wins.
        var seen: [String: Int] = [:]
        var unique: [Match] = []
        for match in found.sorted(by: { ($0.exact ? 0 : 1, -$0.order) < ($1.exact ? 0 : 1, -$1.order) }) {
            let key = rowID(match.request)
            if seen[key] != nil { continue }
            seen[key] = unique.count
            unique.append(match)
        }
        return unique
    }

    static func phraseActions(_ words: [String]) -> [Match] {
        let joined = words.joined(separator: " ")
        var found: [Match] = []
        for (i, setting) in actions.enumerated() {
            var best: Bool?
            for name in setting.names {
                if name.phrase == joined { best = true; break }
                if joined.count >= 3, name.phrase.hasPrefix(joined) { best = best ?? false }
            }
            if let exact = best {
                found.append(Match(request: .action(key: setting.key), exact: exact, order: 100 - i))
            }
        }
        return found
    }

    static func toggleRequests(_ words: [String]) -> [Match] {
        var rest: [String] = []
        var stated: Bool?
        var conflict = false
        for (i, word) in words.enumerated() {
            if onWords.contains(word) || offWords.contains(word) {
                let value = onWords.contains(word)
                if let stated, stated != value { conflict = true }
                stated = value
            } else if i == words.count - 1, i > 0, word == "o" || word == "of" {
                continue // "on" or "off" half typed
            } else {
                rest.append(word)
            }
        }
        guard !conflict, !rest.isEmpty else { return [] }
        let subject = rest.joined(separator: " ")
        let shortest = stated == nil ? 3 : 2
        var found: [Match] = []
        for (i, setting) in toggles.enumerated() {
            var hit: (name: Name, exact: Bool)?
            for name in setting.names {
                if name.phrase == subject { hit = (name, true); break }
                if hit == nil, subject.count >= shortest, name.phrase.hasPrefix(subject) { hit = (name, false) }
            }
            guard let hit else { continue }
            // "light mode on" is dark mode off; "light mode off" is dark mode on;
            // "mic on" is Mute microphone off.
            var desired = stated
            if let implied = hit.name.implies {
                if let stated { desired = stated ? implied : !implied } else { desired = implied }
            } else if hit.name.opposite {
                desired = stated.map { !$0 }
            }
            found.append(Match(request: .toggle(key: setting.key, desired: desired), exact: hit.exact, order: 200 - i))
        }
        return found
    }

    static func volume(_ words: [String]) -> [Match] {
        let first = words[0]
        let rest = Array(words.dropFirst())
        if words.count == 1 {
            switch first {
            case "louder": return [Match(request: .volumeUp, exact: true, order: 300)]
            case "quieter", "softer": return [Match(request: .volumeDown, exact: true, order: 300)]
            default: break
            }
        }
        let named = first == "volume" || first == "vol"
        guard named || (rest.isEmpty && first.count >= 3 && "volume".hasPrefix(first)) else { return [] }
        let exact = named
        guard let word = rest.first, rest.count == 1 else {
            if !rest.isEmpty { return [] }
            return [
                Match(request: .volumeUp, exact: exact, order: 303),
                Match(request: .volumeDown, exact: exact, order: 302),
                Match(request: .toggle(key: "mute", desired: nil), exact: exact, order: 301),
            ]
        }
        if let n = Int(word), word.count <= 3 { return [Match(request: .volumeSet(min(n, 100)), exact: true, order: 300)] }
        switch word {
        case "up", "louder", "higher", "raise": return [Match(request: .volumeUp, exact: true, order: 300)]
        case "down", "lower", "quieter", "softer": return [Match(request: .volumeDown, exact: true, order: 300)]
        case "max", "full", "maximum": return [Match(request: .volumeSet(100), exact: true, order: 300)]
        case "mute", "off": return [Match(request: .toggle(key: "mute", desired: true), exact: true, order: 300)]
        case "unmute", "on": return [Match(request: .toggle(key: "mute", desired: false), exact: true, order: 300)]
        default:
            if "up".hasPrefix(word) { return [Match(request: .volumeUp, exact: false, order: 300)] }
            if "down".hasPrefix(word) { return [Match(request: .volumeDown, exact: false, order: 300)] }
            return []
        }
    }

    /// The row id a request shows as. One row per setting, whatever the phrasing,
    /// so the UI tests can find it: "setting.darkmode", "setting.volume.up".
    public static func rowID(_ request: Request) -> String {
        switch request {
        case .toggle(let key, _), .action(let key): return "setting." + key
        case .volumeSet: return "setting.volume"
        case .volumeUp: return "setting.volume.up"
        case .volumeDown: return "setting.volume.down"
        }
    }
}

// MARK: - State

/// What `toggle status` printed: "wifi on" lines and "volume 40". A setting
/// that is missing could not be read (no Wi-Fi, no blueutil) and shows no state.
public struct SettingsState: Sendable, Equatable {
    public var values: [String: Bool]
    public var volume: Int?

    public init(values: [String: Bool] = [:], volume: Int? = nil) {
        self.values = values
        self.volume = volume
    }

    public static func parse(_ text: String) -> SettingsState {
        var state = SettingsState()
        for line in text.split(separator: "\n") {
            let parts = line.split(separator: " ").map(String.init)
            guard parts.count == 2 else { continue }
            if parts[0] == "volume" {
                if let n = Int(parts[1]), (0...100).contains(n) { state.volume = n }
            } else if parts[1] == "on" || parts[1] == "off" {
                state.values[parts[0]] = parts[1] == "on"
            }
        }
        return state
    }

    /// Takes the values of a read that started at `started` (a number that
    /// grows with each read), unless a value already here came from a read
    /// that started later: a full read begun before a change must not put
    /// back the state from before it. `stamps` holds each value's read
    /// ("volume" for the volume) and is updated.
    public func merging(_ newer: SettingsState, started: Int, stamps: inout [String: Int]) -> SettingsState {
        var merged = self
        for (key, value) in newer.values where (stamps[key] ?? Int.min) <= started {
            merged.values[key] = value
            stamps[key] = started
        }
        if let volume = newer.volume, (stamps[Self.volumeStamp] ?? Int.min) <= started {
            merged.volume = volume
            stamps[Self.volumeStamp] = started
        }
        return merged
    }

    static let volumeStamp = "volume"

    /// `newer` read only some settings: they replace these, the rest stay.
    public func merging(_ newer: SettingsState) -> SettingsState {
        var merged = self
        merged.values.merge(newer.values) { _, new in new }
        if newer.volume != nil { merged.volume = newer.volume }
        return merged
    }

    /// The state a person reads for a toggle setting: Dock autohide on is the Dock not always shown.
    public func shown(_ setting: SettingsActions.Setting) -> Bool? {
        guard case .toggle(_, let stateKey, let inverted) = setting.kind, let value = values[stateKey] else { return nil }
        return inverted ? !value : value
    }
}

/// What a row is doing: nothing, a change in progress, or a change that failed.
public enum SettingPhase: Sendable, Equatable {
    case running(String)
    case failed(SettingFailure)
}

public struct SettingFailure: Sendable, Equatable {
    public let message: String
    public let permission: SettingsActions.Permission?
    /// macOS refused the permission (Automation for System Events, or
    /// Accessibility): the row then says "<Permission> not allowed". false when
    /// the permission is only a likely cause (the change did not take).
    public let refused: Bool

    public init(_ message: String, permission: SettingsActions.Permission? = nil, refused: Bool? = nil) {
        self.message = message
        self.permission = permission
        self.refused = refused ?? (permission != nil)
    }

    /// The row's state: "Automation not allowed", "Accessibility not allowed" or "Failed".
    public var state: String {
        guard refused, let permission else { return "Failed" }
        return permission.title + " not allowed"
    }
}
