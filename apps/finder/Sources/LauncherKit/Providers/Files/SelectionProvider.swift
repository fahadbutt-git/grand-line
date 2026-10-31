import Foundation

/// "selection": Alfred-style actions on the files selected in Nexus or Finder
/// when the window opened (open, show in Nexus, Quick Look, copy paths, names
/// or files, move, AirDrop, move to the Trash, add to the buffer). More words
/// narrow the actions: "selection trash". The window reads the selection the
/// way lib/bin-common.sh's finder_selection does: Nexus's state file when Nexus
/// is in front, else Finder's selection through AppleScript.
public final class SelectionProvider: InstantProvider, @unchecked Sendable {
    public static let providerID = "selection"
    public static let word = "selection"
    public let id = SelectionProvider.providerID
    public let title = "Selection"
    public let symbol = "checklist"
    public let prefix: Prefix? = nil
    public let inGlobalSearch = true
    private let lock = NSLock()
    private var paths: [String] = []
    private var source = ""

    public init() {}

    /// Finder's selection, one POSIX path per line, as finder_selection asks for it.
    public static let finderScript = """
    tell application "Finder" to set sel to selection as alias list
    set out to ""
    repeat with f in sel
      set out to out & POSIX path of f & linefeed
    end repeat
    return out
    """

    /// Paths from Nexus's state file or the script's output: one per line, blanks dropped.
    public static func parse(_ text: String) -> [String] {
        var seen = Set<String>()
        return text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("/") && seen.insert($0).inserted }
    }

    public static func readNexus(_ file: String) -> [String] {
        guard let data = FileManager.default.contents(atPath: file) else { return [] }
        return parse(String(decoding: data, as: UTF8.self))
    }

    /// The selection as the window found it, and where ("Nexus", "Finder").
    public func set(_ paths: [String], from source: String) {
        lock.withLock {
            self.paths = paths
            self.source = source
        }
    }

    public var current: (paths: [String], source: String) { lock.withLock { (paths, source) } }

    /// "sel", "selection", "selection copy": the first word starts "selection".
    static func narrowing(_ term: String) -> String? {
        let words = TextFold.simple(term).split(separator: " ")
        guard let first = words.first, first.count >= 3, word.hasPrefix(first) else { return nil }
        return words.dropFirst().joined(separator: " ")
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        guard query.prefix == nil, let rest = Self.narrowing(query.term) else { return [] }
        let (paths, source) = current
        guard !paths.isEmpty else {
            return [LaunchResult(
                id: "selection:none",
                title: "Nothing is selected in Finder or Nexus",
                subtitle: "Select files there, then open this window and type selection",
                icon: .symbol(symbol),
                section: .files,
                actions: [],
                providerID: id,
                match: MatchInfo(title: .prefix)
            )]
        }
        let names = paths.map { ($0 as NSString).lastPathComponent }
        let summary = (source.isEmpty ? "" : source + " · ") + (names.count <= 3 ? names.joined(separator: ", ") : "\(names.count) items")
        let rows = ActionPanel.fileActions(paths, inBuffer: false).enumerated().map { index, action in
            LaunchResult(
                id: "selection:" + Self.slug(action.title),
                title: action.title,
                subtitle: summary,
                icon: .symbol(action.symbol),
                section: .files,
                keywords: ["selection"],
                accessory: "Selection",
                actions: [action],
                previewPath: paths.count == 1 ? paths[0] : nil,
                providerID: id,
                // In the panel's order: Open first.
                match: MatchInfo(title: .prefix, quality: 1_000 - index)
            )
        }
        guard !rest.isEmpty else { return rows }
        return Catalog(rows.map { var r = $0; r.match = .unmatched; return r }).search(rest)
    }

    static func slug(_ title: String) -> String {
        let first = title.split(separator: " ").prefix(2).joined(separator: "-").lowercased()
        return String(first.filter { $0.isLetter || $0 == "-" }).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }
}
