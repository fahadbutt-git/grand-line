import Foundation

/// The queries you ran something from, newest first, for Up on an empty
/// field (Spotlight, Alfred, KRunner): Up with nothing typed brings back the
/// last query, and Up again, while that query is still showing and the top
/// row is selected, the one before it. Typing anything leaves the history.
/// Kept in memory only, and clipboard history queries (`:`) are never kept.
public struct QueryHistory: Sendable, Equatable {
    public private(set) var entries: [String] = []
    /// Which entry is showing, while Up is walking back through them.
    private var cursor: Int?
    public static let limit = 50

    public init(entries: [String] = []) {
        for entry in entries.reversed() { record(entry) }
    }

    /// Remembers a query something was run from.
    public mutating func record(_ text: String) {
        cursor = nil
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, !Self.isPrivate(trimmed) else { return }
        entries.removeAll { $0 == trimmed }
        entries.insert(trimmed, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
    }

    /// Clipboard history queries name what was copied.
    static func isPrivate(_ text: String) -> Bool {
        text.hasPrefix(Prefix.clipboardHistory.rawValue) && !text.hasPrefix(Prefix.symbols.rawValue)
    }

    /// Up arrow. Returns the query to put in the field, or nil when Up should
    /// move the selection as usual (something typed, or not on the top row).
    public mutating func up(text: String, atTop: Bool) -> String? {
        guard atTop else { return nil }
        if let cursor, entries.indices.contains(cursor), entries[cursor] == text {
            guard cursor + 1 < entries.count else { return nil }
            self.cursor = cursor + 1
            return entries[cursor + 1]
        }
        guard text.isEmpty, let first = entries.first else { return nil }
        cursor = 0
        return first
    }

    /// The field changed by typing: Up starts from the newest again.
    public mutating func leave() {
        cursor = nil
    }

    public var isRecalling: Bool { cursor != nil }
}

/// Reopening soon after closing shows the last query again (select-all, so
/// typing replaces it and Return repeats it, as Raycast does); after
/// `keepFor` the window opens empty, and Up brings the query back.
public enum QueryResume {
    public static let keepFor: TimeInterval = 90

    public static func keepsQuery(hiddenAt: Date?, now: Date) -> Bool {
        guard let hiddenAt else { return true }
        let away = now.timeIntervalSince(hiddenAt)
        return away >= 0 && away <= keepFor
    }
}

/// The placeholder in the empty field: a different example each time the
/// window opens, so what Sight can do is learned by reading it. Nothing runs
/// on a timer; the opening count picks the line.
public enum SearchPlaceholder {
    public static let lines = [
        "Search apps, files and settings",
        "Try \u{201C}dark mode\u{201D} or \u{201C}wifi off\u{201D}",
        "Try \u{201C}5 km in mi\u{201D} or \u{201C}15% of 80\u{201D}",
        "Type ~/ to browse folders, \u{2192} to go into one",
        "Type / to see every prefix",
        "\u{2191} brings back your last search",
    ]

    public static func text(opening: Int) -> String {
        lines[((opening % lines.count) + lines.count) % lines.count]
    }
}
