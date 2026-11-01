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
        let names = try BsdTar.run(["-t", "-P", "-f", archive.path])
        let verbose = try BsdTar.run(["-t", "-v", "-P", "-f", archive.path])
        return listing(archive, names: names, verbose: verbose)
    }

    /// `list` as part of a task: Stop ends bsdtar.
    static func listCancellable(_ archive: URL) async throws -> ArchiveListing {
        let names = try await BsdTar.runCancellable(["-t", "-P", "-f", archive.path])
        let verbose = try await BsdTar.runCancellable(["-t", "-v", "-P", "-f", archive.path])
        return listing(archive, names: names, verbose: verbose)
    }

    static func listing(_ archive: URL, names data: Data, verbose verboseData: Data) -> ArchiveListing {
        let names = BsdTar.lines(data).map(BsdTar.unescape)
        let verbose = BsdTar.lines(verboseData)
        let dates = ListingDates()
        let entries = names.enumerated().map { i, name in
            if verbose.count == names.count {
                return ArchiveEntry.parse(verbose: verbose[i], name: name, dates: dates)
            }
            return ArchiveEntry(name: name, isFolder: name.hasSuffix("/"), size: 0, modified: nil)
        }
        return ArchiveTree.build(entries, archive: archive)
    }

    /// Moves an item to the Trash. Nothing ArchiveKit made is deleted outright
    /// unless it is an empty folder of its own.
    public typealias Trash = @Sendable (URL) throws -> Void

    public static let systemTrash: Trash = { url in
        var result: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &result)
    }

    /// Extracts items (files or whole folders) into `destination`, each under its own
    /// name, as when dragging out of a folder. A name already taken gets " 2".
    /// Returns the extracted items. Items are unpacked into a hidden folder
    /// beside them first; if that fails, what was unpacked goes to the Trash.
    @discardableResult
    public static func extract(_ paths: [String], from archive: URL, to destination: URL) throws -> [URL] {
        let listing = try list(archive)
        let wanted = try check(paths, in: listing)
        let staging = try makeStaging(in: destination)
        do {
            try unpack(wanted, of: listing, into: staging)
            return try finish(wanted, from: archive, staging: staging, into: destination)
        } catch {
            discard(staging, trash: systemTrash)
            throw error
        }
    }

    /// Extract as a task (Cmd+E): cancelling the task stops bsdtar at once,
    /// and the half-unpacked hidden folder goes to the Trash through `trash`.
    @discardableResult
    public static func extract(_ paths: [String], from archive: URL, to destination: URL, trash: @escaping Trash) async throws -> [URL] {
        let listing = try await listCancellable(archive)
        let wanted = try check(paths, in: listing)
        try Task.checkCancellation()
        let staging = try makeStaging(in: destination)
        do {
            try await unpackCancellable(wanted, of: listing, into: staging)
            try Task.checkCancellation()
            return try finish(wanted, from: archive, staging: staging, into: destination)
        } catch {
            discard(staging, trash: trash)
            throw error
        }
    }

    static func makeStaging(in destination: URL) throws -> URL {
        let staging = destination.appendingPathComponent(".extracting-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        return staging
    }

    /// Quarantine first, then each item to a free name beside the hidden folder,
    /// then the hidden folder itself, which is empty by then.
    static func finish(_ wanted: [String], from archive: URL, staging: URL, into destination: URL) throws -> [URL] {
        // Before anything lands where you can open it: a quarantined archive's
        // items keep the quarantine flag (security note L1).
        Quarantine.copy(from: archive, to: wanted.map { staging.appendingPathComponent($0) })
        var results: [URL] = []
        for path in wanted {
            let source = staging.appendingPathComponent(path)
            let name = freeName((path as NSString).lastPathComponent, in: destination)
            let target = destination.appendingPathComponent(name)
            // moveItem refuses a name that is taken, so nothing is written over.
            try FileManager.default.moveItem(at: source, to: target)
            results.append(target)
        }
        discard(staging, trash: systemTrash)
        return results
    }

    /// The hidden unpacking folder once it is done with: removed when empty
    /// (nothing of anyone's in it), otherwise to the Trash.
    static func discard(_ staging: URL, trash: Trash) {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: staging.path) else { return }
        if isEmptyTree(staging) {
            try? fileManager.removeItem(at: staging)
        } else {
            try? trash(staging)
        }
    }

    /// No files below `folder`, only empty folders (what bsdtar leaves of a
    /// folder entry whose items were moved out).
    static func isEmptyTree(_ folder: URL) -> Bool {
        guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: []) else { return true }
        for case let url as URL in walker {
            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isDirectory != true || values?.isSymbolicLink == true { return false }
        }
        return true
    }

    /// Extracts one item into a new temporary folder under `root` and returns
    /// its location there. Quick Look uses `TemporaryFolder.quickLook`, which is
    /// emptied when its panel closes; items opened in an app use their own.
    /// The folder notes each file's size and date as extracted, so cleaning
    /// can tell a copy someone edited and saved from one nobody touched.
    public static func preview(_ path: String, from archive: URL, in root: URL = TemporaryFolder.quickLook) throws -> URL {
        let listing = try list(archive)
        let wanted = try check([path], in: listing)
        let folder = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try unpack(wanted, of: listing, into: folder)
        let item = folder.appendingPathComponent(wanted[0])
        Quarantine.copy(from: archive, to: [item])
        TemporaryFolder.writeManifest(folder)
        return item
    }

    /// Where previews of archive items are written, in $TMPDIR. Each is
    /// cleaned by `TemporaryFolder.clean` (security note L2): Quick Look's when
    /// its panel closes and at launch, the others at launch. A copy that was
    /// changed after it was extracted (edited and saved in an app, marked up in
    /// Quick Look) is someone's work: it goes to the Trash, never deleted.
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

        /// Each copy's size and date when it was extracted, in its folder.
        static let manifestName = ".nexus-extracted.plist"

        struct Stamp: Codable, Equatable {
            let size: Int64
            let modified: Double
        }

        static func stamps(in folder: URL) -> [String: Stamp] {
            var found: [String: Stamp] = [:]
            let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
            guard let walker = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: []) else { return [:] }
            let base = folder.standardizedFileURL.path
            for case let url as URL in walker {
                let values = try? url.resourceValues(forKeys: Set(keys))
                guard values?.isRegularFile == true else { continue }
                let path = url.standardizedFileURL.path
                let relative = path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : url.lastPathComponent
                if relative == manifestName { continue }
                found[relative] = Stamp(size: Int64(values?.fileSize ?? 0),
                                        modified: values?.contentModificationDate?.timeIntervalSinceReferenceDate ?? 0)
            }
            return found
        }

        static func writeManifest(_ folder: URL) {
            guard let data = try? PropertyListEncoder().encode(stamps(in: folder)) else { return }
            try? data.write(to: folder.appendingPathComponent(manifestName))
        }

        /// The files in a copy's folder that are not as they were extracted:
        /// changed, or new (an app's save under another name). Every file when
        /// the folder has no note of how it was.
        static func changedFiles(in folder: URL) -> [URL] {
            let now = stamps(in: folder)
            let manifest = (try? Data(contentsOf: folder.appendingPathComponent(manifestName)))
                .flatMap { try? PropertyListDecoder().decode([String: Stamp].self, from: $0) }
            return now.keys.sorted().filter { manifest?[$0] != now[$0] }.map { folder.appendingPathComponent($0) }
        }

        /// Cleans the copies' folders in `root`, or only those last changed
        /// before `cutoff`. Returns how many went. A folder whose copies are
        /// as they were extracted is removed (Nexus's own copy of what is
        /// still in the archive); a changed or new file in it goes to the Trash
        /// first, and a folder whose changed file cannot go there is kept.
        @discardableResult
        public static func clean(_ root: URL, before cutoff: Date? = nil, trash: Trash = Archive.systemTrash) -> Int {
            let children = (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.contentModificationDateKey], options: []
            )) ?? []
            var removed = 0
            for child in children {
                if let cutoff {
                    let changed = (try? child.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                    if let changed, changed >= cutoff { continue }
                }
                if discard(child, trash: trash) { removed += 1 }
            }
            return removed
        }

        /// Cleans the given copies' folders (Quick Look's, when its panel closes).
        public static func clean(folders: [URL], trash: Trash = Archive.systemTrash) {
            for folder in folders { discard(folder, trash: trash) }
        }

        /// One copy's folder: its edited files to the Trash, then the rest.
        @discardableResult
        static func discard(_ folder: URL, trash: Trash) -> Bool {
            let isFolder = (try? folder.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let edited = isFolder ? changedFiles(in: folder) : [folder]
            for file in edited {
                do {
                    try trash(file)
                } catch {
                    return false
                }
            }
            if !FileManager.default.fileExists(atPath: folder.path) { return true }
            return (try? FileManager.default.removeItem(at: folder)) != nil
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
        let listFile = try patternFile(paths, of: listing)
        defer { try? FileManager.default.removeItem(at: listFile) }
        _ = try BsdTar.run(["-x", "-f", listing.archive.path, "-C", folder.path, "--null", "-T", listFile.path])
    }

    /// `unpack` as part of a task: Stop ends bsdtar.
    static func unpackCancellable(_ paths: [String], of listing: ArchiveListing, into folder: URL) async throws {
        let listFile = try patternFile(paths, of: listing)
        defer { try? FileManager.default.removeItem(at: listFile) }
        _ = try await BsdTar.runCancellable(["-x", "-f", listing.archive.path, "-C", folder.path, "--null", "-T", listFile.path])
    }

    static func patternFile(_ paths: [String], of listing: ArchiveListing) throws -> URL {
        let patterns = paths.map { path -> String in
            var stored = listing.stored[path] ?? path
            while stored.count > 1, stored.hasSuffix("/") { stored.removeLast() }
            return ArchivePath.pattern(stored)
        }
        let listFile = FileManager.default.temporaryDirectory.appendingPathComponent("archive-\(UUID().uuidString).list")
        try Data(patterns.joined(separator: "\0").utf8).write(to: listFile)
        return listFile
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
