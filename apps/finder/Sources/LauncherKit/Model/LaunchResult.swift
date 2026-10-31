import Foundation

/// One row of results.
public struct LaunchResult: Codable, Hashable, Sendable, Identifiable {
    /// Stable across searches, such as "app:/Applications/Safari.app". Usage is learned by it.
    public var id: String
    public var title: String
    public var subtitle: String
    public var icon: ResultIcon
    public var section: ResultSection
    /// Other words the row is found by. A keyword match ranks below a title match.
    public var keywords: [String]
    /// Words that put the row on top when typed in full, such as "pm" for PubMed.
    public var aliases: [String]
    /// The right-hand column: a date, a kind or "On".
    public var accessory: String
    /// Key caps drawn at the right, for shortcuts.
    public var keys: [String]
    public var actions: [LaunchAction]
    /// A file the preview pane can show.
    public var previewPath: String?
    /// Text the preview pane shows when there is no file, such as a definition.
    public var detail: String?
    /// Fallbacks (search the web, ask Claude) always come last.
    public var isFallback: Bool
    public var providerID: String

    /// Filled in while searching; not saved with recents.
    public var match: MatchInfo = .unmatched
    public var rank: RankKey = .unranked

    enum CodingKeys: String, CodingKey {
        case id, title, subtitle, icon, section, keywords, aliases, accessory, keys, actions, previewPath, detail, isFallback, providerID
    }

    public init(
        id: String,
        title: String,
        subtitle: String = "",
        icon: ResultIcon,
        section: ResultSection,
        keywords: [String] = [],
        aliases: [String] = [],
        accessory: String = "",
        keys: [String] = [],
        actions: [LaunchAction],
        previewPath: String? = nil,
        detail: String? = nil,
        isFallback: Bool = false,
        providerID: String = "",
        match: MatchInfo = .unmatched
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.section = section
        self.keywords = keywords
        self.aliases = aliases
        self.accessory = accessory
        self.keys = keys
        self.actions = actions
        self.previewPath = previewPath
        self.detail = detail
        self.isFallback = isFallback
        self.providerID = providerID
        self.match = match
    }

    public var primary: LaunchAction? { actions.first }
    public var secondary: LaunchAction? { actions.count > 1 ? actions[1] : nil }
}
