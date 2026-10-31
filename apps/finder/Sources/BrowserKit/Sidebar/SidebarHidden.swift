import Foundation

/// Built-in sidebar items, saved searches and whole sections hidden from the
/// sidebar, kept in Application Support (sidebar-hidden.json). Show All in
/// Sidebar clears it. Places you added are removed instead, from settings.json.
public struct SidebarHidden: Codable, Equatable, Sendable {
    public var items: [String]
    public var sections: [String]

    public init(items: [String] = [], sections: [String] = []) {
        self.items = items
        self.sections = sections
    }

    public func hides(_ item: SidebarItem) -> Bool { items.contains(item.id) }
    public func hides(_ section: SidebarSection) -> Bool { sections.contains(section.rawValue) }

    public mutating func hide(_ item: SidebarItem) {
        if !items.contains(item.id) { items.append(item.id) }
    }

    public mutating func hide(_ section: SidebarSection) {
        if !sections.contains(section.rawValue) { sections.append(section.rawValue) }
    }
}
