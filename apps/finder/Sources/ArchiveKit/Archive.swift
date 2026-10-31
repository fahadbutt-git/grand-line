import Foundation

/// Archives opened like folders: list the contents, drag items out, preview one.
///
/// ```swift
/// let listing = try Archive.list(url)
/// for item in listing.root.children { ... }
/// let copies = try Archive.extract(["Figures/plot.png"], from: url, to: desktop)
/// let preview = try Archive.preview("README.md", from: url)   // a temporary file for Quick Look
/// ```
///
/// The calls run bsdtar and wait for it, so call them off the main thread.
public enum Archive {
    static let suffixes = [
        ".zip", ".7z", ".rar", ".tar", ".tgz", ".tar.gz", ".tbz", ".tbz2", ".tar.bz2", ".txz", ".tar.xz",
    ]

    public static func isArchive(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return suffixes.contains { name.hasSuffix($0) && name.count > $0.count }
    }

    public static func list(_ archive: URL) throws -> ArchiveListing {
        // -P lists names as stored, so unsafe ones are seen and rejected here
        // rather than silently rewritten by bsdtar.
        let names = BsdTar.lines(try BsdTar.run(["-t", "-P", "-f", archive.path])).map(BsdTar.unescape)
        let verbose = BsdTar.lines(try BsdTar.run(["-t", "-v", "-P", "-f", archive.path]))
        let dates = ListingDates()
        let entries = names.enumerated().map { i, name in
            if verbose.count == names.count {
                return ArchiveEntry.parse(verbose: verbose[i], name: name, dates: dates)
            }
            return ArchiveEntry(name: name, isFolder: name.hasSuffix("/"), size: 0, modified: nil)
        }
        return ArchiveTree.build(entries, archive: archive)
    }

    /// Extracts items (files or whole folders) into `destination`, each under its own
    /// name, as when dragging out of a folder. A name already taken gets " 2".
    /// Returns the extracted items.
    @discardableResult
    public static func extract(_ paths: [String], from archive: URL, to destination: URL) throws -> [URL] {
        let listing = try list(archive)
        let wanted = try check(paths, in: listing)
        let staging = destination.appendingPathComponent(".extracting-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        try unpack(wanted, of: listing, into: staging)
        // Before anything lands where you can open it: a quarantined archive's
        // items keep the quarantine flag (security note L1).
        Quarantine.copy(from: archive, to: wanted.map { staging.appendingPathComponent($0) })

        var results: [URL] = []
        for path in wanted {
            let source = staging.appendingPathComponent(path)
            let name = freeName((path as NSString).lastPathComponent, in: destination)
            let target = destination.appendingPathComponent(name)
            try FileManager.default.moveItem(at: source, to: target)
            results.append(target)
        }
        return results
    }

    /// Extracts one item into a new temporary folder under `root` and returns
    /// its location there. Quick Look uses `TemporaryFolder.quickLook`, which is
    /// emptied when its panel closes; items opened in an app use their own.
    public static func preview(_ path: String, from archive: URL, in root: URL = TemporaryFolder.quickLook) throws -> URL {
        let listing = try list(archive)
        let wanted = try check([path], in: listing)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try unpack(wanted, of: listing, into: folder)
        let item = folder.appendingPathComponent(wanted[0])
        Quarantine.copy(from: archive, to: [item])
        return item
    }

    /// Where previews of archive items are written, in $TMPDIR. Each is
    /// removed by `TemporaryFolder.clean` (security note L2): Quick Look's when
    /// its panel closes and at launch, the others at launch.
    public enum TemporaryFolder {
        /// $TMPDIR/Archive Preview: the Quick Look panel's items.
        public static var quickLook: URL { named("Archive Preview") }
        /// $TMPDIR/Archive Pane: the preview pane's item.
        public static var pane: URL { named("Archive Pane") }
        /// $TMPDIR/Archive Open: items opened in another app, which may still
        /// have them open, so only those older than a day are cleaned.
        public static var opened: URL { named("Archive Open") }

        static func named(_ name: String) -> URL {
            FileManager.default.temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        }

        /// Removes the preview folders in `root`, or only those last changed
        /// before `cutoff`. Returns how many went. These are copies Nexus made
        /// itself, never a person's files.
        @discardableResult
        public static func clean(_ root: URL, before cutoff: Date? = nil) -> Int {
            let fileManager = FileManager.default
            let children = (try? fileManager.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: []
            )) ?? []
            var removed = 0
            for child in children {
                if let cutoff {
                    let changed = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    if let changed, changed >= cutoff { continue }
                }
                if (try? fileManager.removeItem(at: child)) != nil { removed += 1 }
            }
            return removed
        }

        /// At launch: Quick Look's and the pane's folders entirely, opened
        /// items older than a day.
        public static func cleanAtLaunch(now: Date = Date()) {
            clean(quickLook)
            clean(pane)
            clean(opened, before: now.addingTimeInterval(-86_400))
        }
    }

    static func check(_ paths: [String], in listing: ArchiveListing) throws -> [String] {
        try paths.map { path in
            guard ArchivePath.isSafe(path) else { throw ArchiveError.unsafePath(path) }
            let normalized = ArchivePath.normalize(path)
            guard listing.item(at: normalized) != nil else { throw ArchiveError.notInArchive(path) }
            return normalized
        }
    }

    /// Asks bsdtar for exactly these entries (a folder brings everything inside it).
    /// bsdtar also refuses ".." and absolute paths on its own.
    static func unpack(_ paths: [String], of listing: ArchiveListing, into folder: URL) throws {
        let patterns = paths.map { path -> String in
            var stored = listing.stored[path] ?? path
            while stored.count > 1, stored.hasSuffix("/") { stored.removeLast() }
            return ArchivePath.pattern(stored)
        }
        let listFile = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString).list")
        try Data(patterns.joined(separator: "\0").utf8).write(to: listFile)
        defer { try? FileManager.default.removeItem(at: listFile) }
        _ = try BsdTar.run(["-x", "-f", listing.archive.path, "-C", folder.path, "--null", "-T", listFile.path])
    }

    static func freeName(_ name: String, in folder: URL) -> String {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: folder.appendingPathComponent(name).path) else { return name }
        let ext = (name as NSString).pathExtension
        let stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var number = 2
        while true {
            let candidate = ext.isEmpty ? "\(stem) \(number)" : "\(stem) \(number).\(ext)"
            if !fileManager.fileExists(atPath: folder.appendingPathComponent(candidate).path) { return candidate }
            number += 1
        }
    }
}
