import Foundation

/// A permission macOS asks for before a section can show its data.
public enum PanelPermission: String, Sendable, Equatable {
    case calendars, reminders

    public var name: String { self == .calendars ? "Calendars" : "Reminders" }
}

/// Where an item sits in the open panel.
public enum PanelPlacement: String, Sendable, Equatable {
    /// The top band, beside the camera (the date on the left, the battery on the right).
    case header
    /// A column in the main row (Now Playing, Today, Reminders).
    case section
    /// A chip under the columns (script widgets).
    case chip
}

/// A built-in item, as the Settings window lists it.
public struct BuiltinItem: Sendable, Equatable, Identifiable {
    public var id: String
    public var title: String
    public var detail: String
    public var symbol: String
    public var placement: PanelPlacement
    public var permission: PanelPermission?
}

/// Every built-in item Iceberg has.
public enum PanelCatalog {
    public static let builtins: [BuiltinItem] = [
        BuiltinItem(id: "date", title: "Date", detail: "Today's date in the top band, left of the camera.",
                    symbol: "calendar.badge.clock", placement: .header),
        BuiltinItem(id: "now-playing", title: "Now Playing",
                    detail: "What any app is playing, with artwork and controls. Also shows beside the closed notch.",
                    symbol: "play.circle", placement: .section),
        BuiltinItem(id: "today", title: "Today", detail: "What is left of today in every calendar macOS Calendar has.",
                    symbol: "calendar", placement: .section, permission: .calendars),
        BuiltinItem(id: "reminders", title: "Reminders", detail: "Reminders due today or overdue. Tick one to complete it.",
                    symbol: "checklist", placement: .section, permission: .reminders),
        BuiltinItem(id: "battery", title: "Battery", detail: "The charge in the top band, right of the camera.",
                    symbol: "battery.75percent", placement: .header),
        BuiltinItem(id: "shelf", title: "Shelf",
                    detail: "Drag files onto the notch to keep them here, then drag them out to any app. Only a link to each file is kept; the files stay where they are.",
                    symbol: "tray.and.arrow.down", placement: .section),
    ]

    /// What a new install shows. Setup ships no widget turned on, so the
    /// example widgets stay off until you turn them on.
    public static let defaultEnabled = ["date", "now-playing", "today"]

    public static func builtin(_ id: String) -> BuiltinItem? { builtins.first { $0.id == id } }
    public static func isBuiltin(_ id: String) -> Bool { builtin(id) != nil }
}

/// What the panel shows and in what order: one list of names, built-in
/// items and script widgets (by file name) together. It is the `panel` key
/// of iceberg.toml, the one place this is kept.
public struct PanelLayout: Equatable, Sendable {
    /// Every name turned on, in panel order. Names of widgets that are not
    /// there right now are kept, so a widget file that is briefly broken or
    /// moved keeps its place.
    public private(set) var enabled: [String]

    public init(enabled: [String]) {
        var seen = Set<String>()
        self.enabled = enabled.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    /// From the settings: `panel` when set; else a file from before it keeps
    /// its `builtin` list (and the date); else the defaults.
    public init(settings: IcebergSettings) {
        if let panel = settings.panel {
            self.init(enabled: panel)
        } else if settings.builtinIsSet {
            self.init(enabled: ["date"] + settings.builtin)
        } else {
            self.init(enabled: PanelCatalog.defaultEnabled)
        }
    }

    public func isEnabled(_ id: String) -> Bool { enabled.contains(id) }

    /// Turning an item on puts it at the end.
    public mutating func set(_ id: String, enabled on: Bool) {
        if on {
            if !enabled.contains(id) { enabled.append(id) }
        } else {
            enabled.removeAll { $0 == id }
        }
    }

    /// Moves `ids` (which must be on) to just before `target`, or to the end.
    public mutating func move(_ ids: [String], before target: String?) {
        let moving = enabled.filter { ids.contains($0) }
        guard !moving.isEmpty, target.map({ !ids.contains($0) }) ?? true else { return }
        var rest = enabled.filter { !ids.contains($0) }
        let index = target.flatMap { rest.firstIndex(of: $0) } ?? rest.endIndex
        rest.insert(contentsOf: moving, at: index)
        enabled = rest
    }

    /// One place up (-1) or down (+1) among the names in `visible`.
    public mutating func move(_ id: String, by offset: Int, among visible: [String]) {
        let shown = enabled.filter { visible.contains($0) }
        guard let at = shown.firstIndex(of: id) else { return }
        let to = at + offset
        guard to >= 0, to < shown.count else { return }
        if offset < 0 {
            move([id], before: shown[to])
        } else {
            move([id], before: to + 1 < shown.count ? shown[to + 1] : nil)
        }
    }

    /// The built-in items turned on, in order.
    public var builtins: [String] { enabled.filter(PanelCatalog.isBuiltin) }

    /// The widgets turned on that exist, in order. A widget named like a
    /// built-in item cannot be told apart from it, so it is left out.
    public func widgets(available: [String]) -> [String] {
        enabled.filter { !PanelCatalog.isBuiltin($0) && available.contains($0) }
    }

    public var value: TOMLValue { .array(enabled.map { .string($0) }) }
}
