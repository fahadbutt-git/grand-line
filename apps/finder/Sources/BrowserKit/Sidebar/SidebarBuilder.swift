import FileKit
import Foundation

/// Builds the sidebar sections (R29): Places, Active projects, Saved searches and
/// Locations, where every mounted volume shows (internal, external, network),
/// then each Google Drive, then the Trash.
public enum SidebarBuilder {
    public struct Input: Sendable {
        public var home: URL
        public var places: [URL]
        public var projects: [URL]
        public var savedSearches: [String]
        public var volumes: [VolumeInfo]
        public var drives: [GoogleDrive]
        public var trash: URL
        /// Downloads since you last opened the folder, for the "4 new" badge.
        public var newDownloads: Int
        public var hidden: SidebarHidden
        /// Section and item order, and the Tags section (Settings).
        public var layout: SidebarLayout

        public init(
            home: URL, places: [URL], projects: [URL] = [], savedSearches: [String] = [],
            volumes: [VolumeInfo] = [], drives: [GoogleDrive] = [], trash: URL, newDownloads: Int = 0,
            hidden: SidebarHidden = SidebarHidden(), layout: SidebarLayout = SidebarLayout()
        ) {
            self.home = home
            self.places = places
            self.projects = projects
            self.savedSearches = savedSearches
            self.volumes = volumes
            self.drives = drives
            self.trash = trash
            self.newDownloads = newDownloads
            self.hidden = hidden
            self.layout = layout
        }
    }

    /// Finder's favourites, plus home and each drive's My Drive.
    public static func defaultPlaces(home: URL, drives: [GoogleDrive]) -> [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true)]
            + ["Desktop", "Documents", "Downloads"].map { home.appendingPathComponent($0, isDirectory: true) }
            + [home]
            + drives.map(\.myDrive)
    }

    /// Hidden items and sections are left out; a section left empty goes too,
    /// except Locations, which always shows.
    public static func build(_ input: Input) -> [SidebarGroup] {
        everything(input).compactMap { group in
            guard !input.hidden.hides(group.section) else { return nil }
            let items = group.items.filter { !input.hidden.hides($0) }
            guard !items.isEmpty || group.section == .locations else { return nil }
            return SidebarGroup(section: group.section, items: items)
        }
    }

    /// Every section and item in the chosen order, hidden ones included, for
    /// Settings, Sidebar, where they can be shown again.
    public static func everything(_ input: Input) -> [SidebarGroup] {
        input.layout.apply(all(input))
    }

    static func all(_ input: Input) -> [SidebarGroup] {
        var groups: [SidebarGroup] = [SidebarGroup(section: .places, items: places(input))]
        if !input.projects.isEmpty {
            groups.append(SidebarGroup(section: .activeProjects, items: input.projects.map {
                folderItem($0, title: $0.lastPathComponent, symbol: "folder")
            }))
        }
        if !input.savedSearches.isEmpty {
            groups.append(SidebarGroup(section: .savedSearches, items: input.savedSearches.map {
                SidebarItem(id: "search:" + $0, title: $0, symbol: "magnifyingglass", target: .savedSearch($0), removal: .hide)
            }))
        }
        groups.append(SidebarGroup(section: .locations, items: locations(input)))
        if input.layout.showsTags {
            groups.append(SidebarGroup(section: .tags, items: input.layout.tagItems()))
        }
        return groups
    }

    /// Recents and AirDrop first, as in Finder, then the folders.
    static func places(_ input: Input) -> [SidebarItem] {
        var items = [
            SidebarItem(id: "recents", title: "Recents", symbol: "clock", target: .location(.recents)),
            SidebarItem(id: "airdrop", title: "AirDrop", symbol: "dot.radiowaves.left.and.right", target: .airDrop),
        ]
        for url in input.places {
            let drive = input.drives.first { $0.myDrive.standardizedFileURL == url.standardizedFileURL }
            let isHome = url.standardizedFileURL == input.home.standardizedFileURL
            let isDownloads = url.standardizedFileURL == input.home.appendingPathComponent("Downloads").standardizedFileURL
            let title = drive != nil ? "Drive" : (isHome ? input.home.lastPathComponent : url.lastPathComponent)
            let symbol = drive != nil ? "externaldrive.connected.to.line.below" : (isHome ? "house" : FileSymbol.folderSymbol(url.lastPathComponent))
            let badge = isDownloads && input.newDownloads > 0 ? "\(input.newDownloads) new" : nil
            items.append(folderItem(url, title: title, symbol: symbol, badge: badge, removal: .remove))
        }
        return items
    }

    static func locations(_ input: Input) -> [SidebarItem] {
        let volumes = input.volumes.sorted { rank($0) == rank($1) ? $0.name < $1.name : rank($0) < rank($1) }
        var items = volumes.map { volume in
            SidebarItem(
                id: "volume:" + volume.url.path, title: volume.name, symbol: symbol(for: volume),
                target: .location(.folder(volume.url)), detail: ItemFormat.free(volume.availableBytes),
                ejectable: volume.canEject ? volume.url : nil
            )
        }
        for drive in input.drives {
            let title = input.drives.count > 1 ? "Google Drive (\(drive.account))" : "Google Drive"
            items.append(folderItem(drive.root, title: title, symbol: "externaldrive.connected.to.line.below"))
        }
        items.append(SidebarItem(id: "trash", title: "Trash", symbol: "trash", target: .location(.folder(input.trash))))
        return items
    }

    /// The startup disk first, then other internal disks, external drives, network shares.
    static func rank(_ volume: VolumeInfo) -> Int {
        if volume.isRoot { return 0 }
        if volume.isNetwork { return 3 }
        if volume.isInternal && !volume.isRemovable { return 1 }
        return 2
    }

    static func symbol(for volume: VolumeInfo) -> String {
        if volume.isNetwork { return "server.rack" }
        if volume.isRoot || (volume.isInternal && !volume.isRemovable) { return "internaldrive" }
        return "externaldrive"
    }

    static func folderItem(_ url: URL, title: String, symbol: String, badge: String? = nil, removal: SidebarItem.Removal = .hide) -> SidebarItem {
        SidebarItem(
            id: "folder:" + url.standardizedFileURL.path, title: title, symbol: symbol,
            target: .location(.folder(url)), badge: badge, removal: removal
        )
    }
}
