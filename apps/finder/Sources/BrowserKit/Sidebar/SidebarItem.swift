import Foundation

public enum SidebarSection: String, CaseIterable, Sendable {
    case places
    case activeProjects
    case savedSearches
    case locations

    public var title: String {
        switch self {
        case .places: return "Places"
        case .activeProjects: return "Active projects"
        case .savedSearches: return "Saved searches"
        case .locations: return "Locations"
        }
    }
}

public struct SidebarItem: Hashable, Sendable, Identifiable {
    /// What Remove from Sidebar does: a place or saved search you added is
    /// removed from its file; a built-in item is hidden (`SidebarHidden`).
    public enum Removal: Hashable, Sendable {
        case remove
        case hide
    }

    public enum Target: Hashable, Sendable {
        case location(BrowserLocation)
        /// A saved search by name (R18), run when clicked.
        case savedSearch(String)
        /// Finder's AirDrop: opens the AirDrop window; files dropped on it are sent.
        case airDrop
    }

    public let id: String
    public let title: String
    public let symbol: String
    public let target: Target
    /// "1.62 TB free" for a volume.
    public let detail: String?
    /// "4 new" beside Downloads.
    public let badge: String?
    /// The volume to eject with the eject button, when it can be ejected.
    public let ejectable: URL?
    public let removal: Removal

    public init(
        id: String, title: String, symbol: String, target: Target, detail: String? = nil, badge: String? = nil,
        ejectable: URL? = nil, removal: Removal = .hide
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.target = target
        self.detail = detail
        self.badge = badge
        self.ejectable = ejectable
        self.removal = removal
    }

    public var folder: URL? {
        if case .location(let location) = target { return location.folderURL }
        return nil
    }
}

public struct SidebarGroup: Hashable, Sendable, Identifiable {
    public let section: SidebarSection
    public let items: [SidebarItem]
    public var id: String { section.rawValue }

    public init(section: SidebarSection, items: [SidebarItem]) {
        self.section = section
        self.items = items
    }
}
