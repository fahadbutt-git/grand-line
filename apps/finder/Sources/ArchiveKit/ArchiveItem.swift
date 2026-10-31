import Foundation

/// A file or folder inside an archive. Folders that the archive only implies
/// ("a/b.txt" with no "a/" entry) are filled in.
public struct ArchiveItem: Sendable, Equatable {
    /// Relative to the archive root; "" for the root.
    public let path: String
    public let name: String
    public let isFolder: Bool
    /// Uncompressed size; for a folder, everything inside it.
    public let size: Int64
    public let modified: Date?
    /// Folders first, then by name as Finder sorts.
    public let children: [ArchiveItem]

    public init(path: String, name: String, isFolder: Bool, size: Int64, modified: Date?, children: [ArchiveItem]) {
        self.path = path
        self.name = name
        self.isFolder = isFolder
        self.size = size
        self.modified = modified
        self.children = children
    }
}

public struct ArchiveListing: Sendable, Equatable {
    public let archive: URL
    public let root: ArchiveItem
    /// Entries in the archive, not counting implied folders.
    public let entryCount: Int
    /// Entry names that are absolute or contain "..", left out of the tree.
    public let rejected: [String]
    /// Normalized path to the name as stored in the archive.
    let stored: [String: String]

    public func item(at path: String) -> ArchiveItem? {
        let parts = ArchivePath.normalize(path).split(separator: "/").map(String.init)
        var current = root
        for part in parts {
            guard let next = current.children.first(where: { $0.name == part }) else { return nil }
            current = next
        }
        return current
    }
}

/// One line of `bsdtar -tv`, paired with its exact name from `bsdtar -t`.
struct ArchiveEntry: Equatable {
    let name: String
    let isFolder: Bool
    let size: Int64
    let modified: Date?

    /// Mode, links, owner, group, size, month, day, time or year, then the name.
    static func parse(verbose line: String, name: String, dates: ListingDates = ListingDates()) -> ArchiveEntry {
        let fields = line.split(separator: " ", maxSplits: 8, omittingEmptySubsequences: true)
        let isFolder = name.hasSuffix("/") || fields.first?.first == "d"
        guard fields.count >= 8 else {
            return ArchiveEntry(name: name, isFolder: isFolder, size: 0, modified: nil)
        }
        let size = Int64(fields[4]) ?? 0
        let modified = dates.date(month: String(fields[5]), day: String(fields[6]), timeOrYear: String(fields[7]))
        return ArchiveEntry(name: name, isFolder: isFolder, size: isFolder ? 0 : size, modified: modified)
    }
}

/// Reads `bsdtar -tv` dates: "Oct 31 12:00" (within the last half year) or "Oct 31 2025".
/// Made once per listing, since setting up a formatter costs more than using it.
struct ListingDates {
    let now: Date
    private let recent = ListingDates.formatter("MMM d HH:mm yyyy")
    private let older = ListingDates.formatter("MMM d yyyy")

    init(now: Date = Date()) {
        self.now = now
    }

    func date(month: String, day: String, timeOrYear: String) -> Date? {
        guard timeOrYear.contains(":") else {
            return older.date(from: "\(month) \(day) \(timeOrYear)")
        }
        let year = Calendar.current.component(.year, from: now)
        guard let date = recent.date(from: "\(month) \(day) \(timeOrYear) \(year)") else { return nil }
        if date > now.addingTimeInterval(86_400) {
            return recent.date(from: "\(month) \(day) \(timeOrYear) \(year - 1)")
        }
        return date
    }

    private static func formatter(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }
}

/// Builds the tree from flat entries.
enum ArchiveTree {
    struct Node {
        var isFolder = true
        var size: Int64 = 0
        var modified: Date?
        var children: Set<String> = []
    }

    static func build(_ entries: [ArchiveEntry], archive: URL) -> ArchiveListing {
        var nodes: [String: Node] = ["": Node()]
        var rejected: [String] = []
        var stored: [String: String] = [:]
        var count = 0
        for entry in entries {
            // "./" is the archive's own root.
            if ArchivePath.normalize(entry.name).isEmpty, !entry.name.hasPrefix("/") { continue }
            guard ArchivePath.isSafe(entry.name) else {
                rejected.append(entry.name)
                continue
            }
            let path = ArchivePath.normalize(entry.name)
            // macOS's own leftovers (__MACOSX/, ._ files, .DS_Store) stay hidden, as in folders.
            if ArchivePath.isMacMetadata(path) { continue }
            count += 1
            if stored[path] == nil { stored[path] = entry.name }
            var node = nodes[path] ?? Node()
            node.isFolder = entry.isFolder || !(nodes[path]?.children.isEmpty ?? true)
            node.size = entry.size
            node.modified = entry.modified
            nodes[path] = node
            var child = path
            while !child.isEmpty {
                let parent = (child as NSString).deletingLastPathComponent
                var parentNode = nodes[parent] ?? Node()
                parentNode.isFolder = true
                let inserted = parentNode.children.insert(child).inserted
                nodes[parent] = parentNode
                if !inserted { break }
                child = parent
            }
        }
        let root = item("", nodes)
        return ArchiveListing(archive: archive, root: root, entryCount: count, rejected: rejected, stored: stored)
    }

    static func item(_ path: String, _ nodes: [String: Node]) -> ArchiveItem {
        let node = nodes[path] ?? Node()
        let children = node.children.map { item($0, nodes) }.sorted { a, b in
            if a.isFolder != b.isFolder { return a.isFolder }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
        let size = node.isFolder ? children.reduce(Int64(0)) { $0 + $1.size } : node.size
        return ArchiveItem(
            path: path,
            name: path.isEmpty ? "" : (path as NSString).lastPathComponent,
            isFolder: node.isFolder,
            size: size,
            modified: node.modified,
            children: children
        )
    }
}
