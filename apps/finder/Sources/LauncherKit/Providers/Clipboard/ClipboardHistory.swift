import Foundation
import SQLite3

/// One entry of Maccy's clipboard history.
public struct ClipEntry: Sendable, Equatable {
    public let id: Int
    public let text: String
    public let app: String
    public let copied: Date?
    public let pinned: Bool

    public init(id: Int, text: String, app: String = "", copied: Date? = nil, pinned: Bool = false) {
        self.id = id
        self.text = text
        self.app = app
        self.copied = copied
        self.pinned = pinned
    }
}

/// Maccy's history, read only. Maccy has no API, so its store (SwiftData's
/// Storage.sqlite in its sandbox container) is copied with its write-ahead log
/// and the copy is read; Maccy's own file is never opened, and its external
/// blobs folder and shared-memory file are never copied. The copy is made only
/// when the store or its log changed since the last read. Only text entries
/// are listed. When the store is not where Maccy keeps it, `:` is hidden and
/// keeps its older meaning (symbols).
public enum ClipboardHistory {
    /// Where Maccy keeps its history: the sandbox container, or the plain
    /// Application Support folder of builds without the sandbox.
    public static func stores(_ paths: GrandLinePaths = GrandLinePaths()) -> [String] {
        [paths.maccyStore, paths.home + "/Library/Application Support/Maccy/Storage.sqlite"]
    }

    public static func store(_ paths: GrandLinePaths = GrandLinePaths(), fileManager: FileManager = .default) -> String? {
        stores(paths).first { fileManager.fileExists(atPath: $0) }
    }

    public static func isAvailable(_ paths: GrandLinePaths = GrandLinePaths()) -> Bool {
        store(paths) != nil
    }

    /// What a read of the store depends on: the size and modification date of
    /// the store and of its write-ahead log. The same signature means the same
    /// entries, so nothing is copied.
    public struct Signature: Sendable, Equatable {
        public let parts: [String]
    }

    public static func signature(of database: String, fileManager: FileManager = .default) -> Signature? {
        var parts: [String] = []
        for suffix in ["", "-wal"] {
            guard let attributes = try? fileManager.attributesOfItem(atPath: database + suffix) else {
                if suffix.isEmpty { return nil }
                parts.append("-")
                continue
            }
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? -1
            let date = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
            parts.append("\(size):\(date)")
        }
        return Signature(parts: [database] + parts)
    }

    /// Core Data and SwiftData keep dates as seconds since 2001.
    static let referenceDate = Date(timeIntervalSinceReferenceDate: 0)

    static let query = """
    SELECT i.Z_PK, COALESCE(i.ZTITLE, ''), COALESCE(i.ZAPPLICATION, ''), COALESCE(i.ZLASTCOPIEDAT, 0), i.ZPIN, c.ZVALUE
    FROM ZHISTORYITEM i
    LEFT JOIN ZHISTORYITEMCONTENT c ON c.ZITEM = i.Z_PK AND c.ZTYPE = 'public.utf8-plain-text'
    ORDER BY i.ZLASTCOPIEDAT DESC
    LIMIT ?
    """

    /// The newest text entries, pinned ones first. Empty when the store cannot be read.
    public static func load(_ database: String, limit: Int = 300, fileManager: FileManager = .default) -> [ClipEntry] {
        let copy = fileManager.temporaryDirectory.appendingPathComponent("sight-clipboard-\(UUID().uuidString)").path
        defer {
            for suffix in ["", "-wal", "-shm"] { try? fileManager.removeItem(atPath: copy + suffix) }
        }
        for suffix in ["", "-wal"] where fileManager.fileExists(atPath: database + suffix) {
            try? fileManager.copyItem(atPath: database + suffix, toPath: copy + suffix)
        }
        var handle: OpaquePointer?
        guard sqlite3_open_v2(copy, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db = handle else {
            sqlite3_close(handle)
            return []
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK, let rows = statement else { return [] }
        defer { sqlite3_finalize(rows) }
        sqlite3_bind_int(rows, 1, Int32(limit))
        var entries: [ClipEntry] = []
        var seen = Set<Int>()
        while sqlite3_step(rows) == SQLITE_ROW {
            let id = Int(sqlite3_column_int64(rows, 0))
            guard seen.insert(id).inserted else { continue }
            let title = sqlite3_column_text(rows, 1).map { String(cString: $0) } ?? ""
            let app = sqlite3_column_text(rows, 2).map { String(cString: $0) } ?? ""
            let seconds = sqlite3_column_double(rows, 3)
            let pinned = sqlite3_column_type(rows, 4) != SQLITE_NULL
            var text = title
            if sqlite3_column_type(rows, 5) != SQLITE_NULL, let blob = sqlite3_column_blob(rows, 5) {
                let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(rows, 5)))
                if let value = String(data: data, encoding: .utf8), !value.isEmpty { text = value }
            }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            entries.append(ClipEntry(id: id, text: text, app: app,
                                     copied: seconds > 0 ? Date(timeIntervalSinceReferenceDate: seconds) : nil, pinned: pinned))
        }
        return entries.filter(\.pinned) + entries.filter { !$0.pinned }
    }

    /// The app's name from its bundle id or path ("com.apple.Safari" → "Safari").
    static func appName(_ app: String) -> String {
        let last = app.split(separator: "/").last.map(String.init) ?? app
        if last.hasSuffix(".app") { return String(last.dropLast(4)) }
        return last.split(separator: ".").last.map(String.init) ?? last
    }

    public static func results(_ entries: [ClipEntry], now: Date = Date()) -> [LaunchResult] {
        entries.map { entry in
            let line = entry.text.split(whereSeparator: \.isNewline).first.map(String.init) ?? entry.text
            let title = line.trimmingCharacters(in: .whitespaces)
            let shown = title.count > 200 ? String(title.prefix(200)) + "…" : title
            var subtitle = appName(entry.app)
            if let copied = entry.copied { subtitle += (subtitle.isEmpty ? "" : " · ") + DateText.relative(copied, now: now) }
            return LaunchResult(
                id: "clip:\(entry.id)",
                title: shown.isEmpty ? "(whitespace)" : shown,
                subtitle: subtitle,
                icon: .symbol(entry.pinned ? "pin" : "doc.on.clipboard"),
                section: .answers,
                keywords: [String(entry.text.prefix(500))],
                accessory: entry.pinned ? "Pinned" : "",
                actions: [
                    LaunchAction("Paste", symbol: "doc.on.clipboard", .paste(entry.text)),
                    LaunchAction("Copy", symbol: "doc.on.doc", shortcut: KeyShortcut("c", shift: true), .copyText(entry.text)),
                ],
                detail: entry.text,
                providerID: ClipboardHistoryProvider.providerID
            )
        }
    }
}

/// `:` Maccy's clipboard history, read only. Read again each time the window
/// opens; hidden while Maccy's store is missing.
public final class ClipboardHistoryProvider: InstantProvider, @unchecked Sendable {
    public static let providerID = "clipboard-history"
    public let id = ClipboardHistoryProvider.providerID
    public let title = "Clipboard history"
    public let symbol = "doc.on.clipboard"
    public let prefix: Prefix? = .clipboardHistory
    public let inGlobalSearch = false
    let paths: GrandLinePaths
    let catalog = Catalog()
    let loader: @Sendable (String) -> [ClipEntry]
    private let lock = NSLock()
    /// One reload at a time: opening the window quickly twice does not copy twice.
    private var reloading = false
    private var loaded: (signature: ClipboardHistory.Signature, entries: [ClipEntry])?

    public init(paths: GrandLinePaths = GrandLinePaths(), loader: @escaping @Sendable (String) -> [ClipEntry] = { ClipboardHistory.load($0) }) {
        self.paths = paths
        self.loader = loader
    }

    /// Reads the history again when Maccy's store changed; otherwise only the
    /// "2 min ago" dates are brought up to now. A reload already under way
    /// makes this one return at once. Blocks on the disk: call it off the main thread.
    public func reload(now: Date = Date()) {
        let claimed = lock.withLock { () -> Bool in
            guard !reloading else { return false }
            reloading = true
            return true
        }
        guard claimed else { return }
        defer { lock.withLock { reloading = false } }
        guard let store = ClipboardHistory.store(paths), let signature = ClipboardHistory.signature(of: store) else {
            lock.withLock { loaded = nil }
            catalog.replace([])
            return
        }
        let cached = lock.withLock { loaded }
        let entries: [ClipEntry]
        if let cached, cached.signature == signature {
            entries = cached.entries
        } else {
            entries = loader(store)
            lock.withLock { loaded = (signature, entries) }
        }
        catalog.replace(ClipboardHistory.results(entries, now: now))
    }

    public func replace(_ entries: [ClipEntry], now: Date = Date()) {
        catalog.replace(ClipboardHistory.results(entries, now: now))
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        guard query.prefix == .clipboardHistory else { return [] }
        let found = catalog.search(query.term, limit: 300)
        guard query.term.isEmpty else { return found }
        // Newest first, as Maccy lists them.
        return found.enumerated().map { index, row in
            var r = row
            r.match = MatchInfo(title: .prefix, quality: 100_000 - index)
            return r
        }
    }
}
