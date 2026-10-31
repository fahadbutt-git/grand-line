import Foundation

/// The sidebar's order and its Tags section, from Settings, Sidebar and
/// Tags. Hidden items stay in sidebar-hidden.json (`SidebarHidden`).
public struct SidebarLayout: Equatable, Sendable {
    public enum Key {
        public static let sectionOrder = "SidebarSectionOrder"
        public static let itemOrder = "SidebarItemOrder"
        public static let tags = "SidebarTags"
        public static let favouriteTags = "FavouriteTags"
    }

    /// Every section, in the order shown.
    public private(set) var sectionOrder: [SidebarSection]
    /// Section name to item ids, for the items moved by hand. Others follow in their own order.
    public var itemOrder: [String: [String]]
    /// The tags with an entry in the sidebar's Tags section, in order. None by default.
    public var tags: [String]
    /// Tags offered as one-click chips in the inspector.
    public var favouriteTags: [String]

    public static let standardTags = TagEditor.colors

    public init(sectionOrder: [SidebarSection] = SidebarSection.allCases, itemOrder: [String: [String]] = [:],
                tags: [String] = [], favouriteTags: [String] = TagEditor.colors) {
        var seen = Set<SidebarSection>()
        var full = sectionOrder.filter { seen.insert($0).inserted }
        for section in SidebarSection.allCases where !seen.contains(section) { full.append(section) }
        self.sectionOrder = full
        self.itemOrder = itemOrder
        self.tags = Self.unique(tags)
        self.favouriteTags = Self.unique(favouriteTags)
    }

    public init(defaults: UserDefaults) {
        self.init(
            sectionOrder: (defaults.stringArray(forKey: Key.sectionOrder) ?? []).compactMap(SidebarSection.init(rawValue:)),
            itemOrder: defaults.dictionary(forKey: Key.itemOrder) as? [String: [String]] ?? [:],
            tags: defaults.stringArray(forKey: Key.tags) ?? [],
            favouriteTags: defaults.stringArray(forKey: Key.favouriteTags) ?? TagEditor.colors
        )
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(sectionOrder.map(\.rawValue), forKey: Key.sectionOrder)
        defaults.set(itemOrder, forKey: Key.itemOrder)
        defaults.set(tags, forKey: Key.tags)
        defaults.set(favouriteTags, forKey: Key.favouriteTags)
    }

    static func unique(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
    }

    // MARK: Ordering

    /// Sections in `sectionOrder`, and the items of each in `itemOrder`
    /// (items not listed keep their order, after the listed ones).
    public func apply(_ groups: [SidebarGroup]) -> [SidebarGroup] {
        groups
            .sorted { rank($0.section) < rank($1.section) }
            .map { SidebarGroup(section: $0.section, items: ordered($0.items, in: $0.section)) }
    }

    func rank(_ section: SidebarSection) -> Int {
        sectionOrder.firstIndex(of: section) ?? sectionOrder.count
    }

    func ordered(_ items: [SidebarItem], in section: SidebarSection) -> [SidebarItem] {
        guard let order = itemOrder[section.rawValue], !order.isEmpty else { return items }
        let place = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        return items.enumerated().sorted { a, b in
            let x = place[a.element.id] ?? (order.count + a.offset)
            let y = place[b.element.id] ?? (order.count + b.offset)
            return x < y
        }.map(\.element)
    }

    public mutating func move(_ section: SidebarSection, by offset: Int) {
        guard let from = sectionOrder.firstIndex(of: section) else { return }
        let to = min(max(from + offset, 0), sectionOrder.count - 1)
        guard to != from else { return }
        sectionOrder.remove(at: from)
        sectionOrder.insert(section, at: to)
    }

    /// Moves an item within its section; `shown` is the section's items as now ordered.
    public mutating func move(item id: String, in section: SidebarSection, by offset: Int, shown: [String]) {
        var ids = shown
        guard let from = ids.firstIndex(of: id) else { return }
        let to = min(max(from + offset, 0), ids.count - 1)
        guard to != from else { return }
        ids.remove(at: from)
        ids.insert(id, at: to)
        itemOrder[section.rawValue] = ids
    }

    // MARK: Tags

    public var showsTags: Bool { !tags.isEmpty }

    public mutating func setTag(_ tag: String, shown: Bool) {
        if shown { tags = Self.unique(tags + [tag]) } else { tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame } }
    }

    public mutating func setTag(_ tag: String, favourite: Bool) {
        if favourite {
            favouriteTags = Self.unique(favouriteTags + [tag])
        } else {
            favouriteTags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
    }

    /// The Tags section's entries: each runs a home-folder search for the tag.
    public func tagItems() -> [SidebarItem] {
        tags.map { tag in
            SidebarItem(id: "tag:" + tag, title: tag, symbol: "tag",
                        target: .location(.search(query: Self.query(for: tag), scope: .home)))
        }
    }

    /// `tag:Red`, or `tag:"In review"` for a name with a space.
    public static func query(for tag: String) -> String {
        tag.contains(" ") ? "tag:\"\(tag)\"" : "tag:\(tag)"
    }
}
