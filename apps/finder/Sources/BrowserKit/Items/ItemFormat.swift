import Foundation

/// How sizes, dates and counts read in rows, the footer and the inspector.
public enum ItemFormat {
    /// "412 KB", "1.62 TB": 1000-based like Finder.
    public static func size(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    /// "Today, 9:41", "Yesterday, 16:02", "Oct 24, 2026".
    public static func date(_ date: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        let time = DateFormatter()
        time.locale = locale
        time.calendar = calendar
        time.timeZone = calendar.timeZone
        time.dateStyle = .none
        time.timeStyle = .short
        if calendar.isDate(date, inSameDayAs: now) { return "Today, " + time.string(from: date) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday, " + time.string(from: date)
        }
        let day = DateFormatter()
        day.locale = locale
        day.calendar = calendar
        day.timeZone = calendar.timeZone
        day.dateStyle = .medium
        day.timeStyle = .none
        return day.string(from: date)
    }

    /// "1 item", "14 items".
    public static func count(_ n: Int, _ noun: String = "item") -> String {
        n == 1 ? "1 \(noun)" : "\(n) \(noun)s"
    }

    /// The footer's left side: "3 of 9 selected · 18.6 MB", or "9 items".
    public static func status(selected: Int, total: Int, selectedBytes: Int64?) -> String {
        guard selected > 0 else { return count(total) }
        var text = "\(selected) of \(total) selected"
        if let selectedBytes { text += " · " + size(selectedBytes) }
        return text
    }

    /// The footer's left side in a search that looks inside files: how many
    /// rows were found by name and how many only inside, so a long list of
    /// content matches is never mistaken for name matches: "12 by name ·
    /// 1,594 inside files", "12 by name · inside files hidden". A selection
    /// reads as anywhere else; a search with no inside-file rows as "12 items".
    public static func searchStatus(_ counts: SearchCounts?, selected: Int, total: Int, selectedBytes: Int64?) -> String {
        guard selected == 0, let counts else { return status(selected: selected, total: total, selectedBytes: selectedBytes) }
        if counts.insideFilesHidden { return grouped(counts.byName) + " by name · inside files hidden" }
        guard counts.insideFiles > 0 else { return count(total) }
        return grouped(counts.byName) + " by name · " + grouped(counts.insideFiles) + " inside files"
    }

    /// The header before the files found only inside: "Found inside files (1,594)".
    public static func insideFilesHeader(_ count: Int) -> String {
        "Found inside files (" + grouped(count) + ")"
    }

    /// 1594 as "1,594".
    public static func grouped(_ n: Int) -> String {
        let digits = String(abs(n))
        var out = ""
        for (i, c) in digits.enumerated() {
            if i > 0, (digits.count - i) % 3 == 0 { out.append(",") }
            out.append(c)
        }
        return (n < 0 ? "-" : "") + out
    }

    /// The footer's right side: "1.62 TB free".
    public static func free(_ bytes: Int64) -> String {
        size(bytes) + " free"
    }
}
