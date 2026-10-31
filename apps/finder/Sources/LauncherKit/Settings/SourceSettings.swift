import Foundation

/// A kind of result that can be turned off or moved in Settings, Sources.
public enum LauncherSource: String, CaseIterable, Sendable, Codable {
    // In the default order, which gives the sections their default order.
    case calculator
    case units
    case apps
    case commands
    case menu
    case windows
    case settingsActions = "settings"
    case bookmarks
    case snippets
    case files
    case webFallbacks = "fallbacks"

    public var title: String {
        switch self {
        case .apps: return "Apps"
        case .calculator: return "Calculator, dates and time zones"
        case .units: return "Units and currency"
        case .commands: return "Grand Line commands"
        case .menu: return "Grand Line menu"
        case .windows: return "Open windows"
        case .settingsActions: return "Settings you can change"
        case .bookmarks: return "Bookmarks (Zen)"
        case .snippets: return "Snippets (Espanso)"
        case .files: return "Files and folders"
        case .webFallbacks: return "Web fallbacks"
        }
    }

    public var detail: String {
        switch self {
        case .apps: return "Apps in Applications and the system folders."
        case .calculator: return "Sums, dates and time zones typed anywhere."
        case .units: return "\u{201C}5 km in mi\u{201D}, \u{201C}100 usd\u{201D}, with Bank of Canada rates."
        case .commands: return "Every command in the package's bin folder, with its arguments."
        case .menu: return "The main menu's entries, such as Toggle and Capture."
        case .windows: return "Windows of the running apps."
        case .settingsActions: return "\u{201C}wifi off\u{201D}, \u{201C}dark mode\u{201D}, \u{201C}volume 30\u{201D}, changed in place."
        case .bookmarks: return "Bookmarks from Zen's profile."
        case .snippets: return "Espanso's text shortcuts."
        case .files: return "Names from the home folder's index, contents from Spotlight."
        case .webFallbacks: return "Search the web or ask an assistant, at the bottom of every search."
        }
    }

    public var symbol: String {
        switch self {
        case .apps: return "square.grid.2x2"
        case .calculator: return "equal.square"
        case .units: return "ruler"
        case .commands: return "terminal"
        case .menu: return "menubar.rectangle"
        case .windows: return "macwindow.on.rectangle"
        case .settingsActions: return "switch.2"
        case .bookmarks: return "bookmark"
        case .snippets: return "text.quote"
        case .files: return "doc.text.magnifyingglass"
        case .webFallbacks: return "arrow.turn.down.right"
        }
    }

    /// The prefix that shows this source alone, if it has one.
    public var prefix: Prefix? {
        switch self {
        case .calculator, .units: return .calculator
        case .windows: return .windows
        case .bookmarks: return .bookmarks
        case .snippets: return .snippets
        case .files: return .files
        case .apps, .commands, .menu, .settingsActions, .webFallbacks: return nil
        }
    }

    /// The providers (by id) this source turns on and off. Units share the
    /// calculator's provider, which is told what to answer.
    public var providerIDs: [String] {
        switch self {
        case .apps: return ["apps"]
        case .calculator, .units: return ["calculator"]
        case .commands: return ["commands"]
        case .menu: return ["menu"]
        case .windows: return ["windows"]
        case .settingsActions: return [SettingsActionsProvider.providerID]
        case .bookmarks: return ["bookmarks"]
        case .snippets: return ["snippets"]
        case .files: return ["files"]
        case .webFallbacks: return ["fallbacks"]
        }
    }

    /// The section its rows appear in.
    public var section: ResultSection {
        switch self {
        case .apps: return .apps
        case .calculator, .units: return .answers
        case .commands, .menu: return .grandLine
        case .windows: return .windows
        case .settingsActions: return .system
        case .bookmarks: return .bookmarks
        case .snippets: return .snippets
        case .files: return .files
        case .webFallbacks: return .web
        }
    }
}

/// Which sources are on and in what order, kept in Sight's defaults as two
/// string lists (`SourceOrder`, `DisabledSources`). Unknown names are dropped
/// and sources missing from a saved order keep their default place.
public struct SourceSettings: Sendable, Equatable {
    public static let orderKey = "SourceOrder"
    public static let disabledKey = "DisabledSources"

    public private(set) var order: [LauncherSource]
    public private(set) var disabled: Set<LauncherSource>

    public init(order: [LauncherSource] = LauncherSource.allCases, disabled: Set<LauncherSource> = []) {
        var seen = Set<LauncherSource>()
        var full = order.filter { seen.insert($0).inserted }
        // A source added since the order was saved goes at the end.
        for source in LauncherSource.allCases where !seen.contains(source) { full.append(source) }
        self.order = full
        self.disabled = disabled
    }

    public static let standard = SourceSettings()

    /// From the stored lists, as `defaultsValue` writes them.
    public init(order stored: [String]?, disabled storedOff: [String]?) {
        self.init(order: (stored ?? []).compactMap(LauncherSource.init(rawValue:)),
                  disabled: Set((storedOff ?? []).compactMap(LauncherSource.init(rawValue:))))
    }

    public var storedOrder: [String] { order.map(\.rawValue) }
    public var storedDisabled: [String] { LauncherSource.allCases.filter { disabled.contains($0) }.map(\.rawValue) }

    public func isEnabled(_ source: LauncherSource) -> Bool { !disabled.contains(source) }

    public mutating func set(_ source: LauncherSource, enabled: Bool) {
        if enabled { disabled.remove(source) } else { disabled.insert(source) }
    }

    /// Moves one source up (negative) or down (positive) by `offset` places.
    public mutating func move(_ source: LauncherSource, by offset: Int) {
        guard let from = order.firstIndex(of: source) else { return }
        let to = min(max(from + offset, 0), order.count - 1)
        guard to != from else { return }
        order.remove(at: from)
        order.insert(source, at: to)
    }

    /// Drag and drop: the sources at `offsets` go before `destination`, as SwiftUI's onMove gives them.
    public mutating func move(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        let valid = offsets.filter { $0 < order.count }
        let moving = valid.map { order[$0] }
        var rest = order
        for index in valid.reversed() { rest.remove(at: index) }
        let at = min(max(destination - valid.filter { $0 < destination }.count, 0), rest.count)
        rest.insert(contentsOf: moving, at: at)
        order = rest
    }

    /// Whether a provider runs at all: off only when every source it serves is off.
    public func runs(providerID: String) -> Bool {
        let owners = LauncherSource.allCases.filter { $0.providerIDs.contains(providerID) }
        return owners.isEmpty || owners.contains { isEnabled($0) }
    }

    /// The section order the sources give: the favourites, recents and top hit
    /// first, then each source's section in the sources' order. Sections no
    /// source names (symbols) keep their place after their default neighbour.
    public var sectionOrder: [ResultSection] {
        var sections: [ResultSection] = [.favourites, .recents, .topHit]
        for source in order where !sections.contains(source.section) { sections.append(source.section) }
        for (index, section) in ResultSection.allCases.enumerated() where !sections.contains(section) {
            let before = ResultSection.allCases[..<index].last { sections.contains($0) }
            let at = before.flatMap { sections.firstIndex(of: $0) }.map { $0 + 1 } ?? sections.count
            sections.insert(section, at: at)
        }
        return sections
    }
}
