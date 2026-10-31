import Foundation

/// Dates and times the calculator reads: "today + 30 days", "dec 25 - today",
/// "days until 2027-01-15", "time in tokyo", "3pm toronto in london".
public struct DateMath: Sendable {
    public let now: Date
    public let calendar: Calendar

    public init(now: Date = Date(), calendar: Calendar = .current) {
        self.now = now
        var calendar = calendar
        calendar.locale = Locale(identifier: "en_US_POSIX")
        self.calendar = calendar
    }

    public struct Answer: Sendable, Equatable {
        public let text: String
        public let copy: String
    }

    public func evaluate(_ input: String) -> Answer? {
        let text = input.lowercased().trimmingCharacters(in: .whitespaces)
        if let answer = timeZoneAnswer(text) { return answer }
        if let answer = untilOrSince(text) { return answer }
        if let answer = arithmetic(text) { return answer }
        return nil
    }

    // MARK: Time zones

    func timeZoneAnswer(_ text: String) -> Answer? {
        // "time in tokyo", "now in tokyo", "tokyo time"
        for lead in ["time in ", "now in ", "what time in "] where text.hasPrefix(lead) {
            return timeIn(String(text.dropFirst(lead.count)), at: now)
        }
        if text.hasSuffix(" time"), let answer = timeIn(String(text.dropLast(5)), at: now) { return answer }
        // "3pm toronto in london", "15:30 utc to est", "3pm in tokyo"
        guard let pair = splitConversion(text), let target = TimeZones.zone(pair.1) else { return nil }
        let (left, right) = pair
        let words = left.split(separator: " ").map(String.init)
        guard let first = words.first, let clock = Self.clock(first) else { return nil }
        let sourceName = words.dropFirst().joined(separator: " ")
        let source: TimeZone
        if sourceName.isEmpty {
            source = calendar.timeZone
        } else if let named = TimeZones.zone(sourceName) {
            source = named
        } else {
            return nil
        }
        var sourceCalendar = calendar
        sourceCalendar.timeZone = source
        var parts = sourceCalendar.dateComponents([.year, .month, .day], from: now)
        parts.hour = clock.hour
        parts.minute = clock.minute
        guard let instant = sourceCalendar.date(from: parts) else { return nil }
        let shown = format(instant, zone: target, "h:mm a")
        let day = format(instant, zone: target, "EEE, MMM d")
        return Answer(text: "\(shown) in \(TimeZones.label(right)) (\(day))", copy: shown)
    }

    func timeIn(_ place: String, at date: Date) -> Answer? {
        guard let zone = TimeZones.zone(place) else { return nil }
        let shown = format(date, zone: zone, "h:mm a")
        return Answer(text: "\(shown) in \(TimeZones.label(place)) (\(format(date, zone: zone, "EEE, MMM d")))", copy: shown)
    }

    /// "3pm", "3:30 pm", "15:30", "noon", "midnight", "now".
    static func clock(_ text: String) -> (hour: Int, minute: Int)? {
        switch text {
        case "noon": return (12, 0)
        case "midnight": return (0, 0)
        default: break
        }
        var body = text
        var meridiem: String?
        for suffix in ["am", "pm", "a", "p"] where body.hasSuffix(suffix) {
            meridiem = suffix.hasPrefix("a") ? "am" : "pm"
            body = String(body.dropLast(suffix.count))
            break
        }
        let parts = body.split(separator: ":")
        guard (1...2).contains(parts.count), let hour = Int(parts[0]) else { return nil }
        let minute = parts.count == 2 ? Int(parts[1]) : 0
        guard let minute, (0..<60).contains(minute) else { return nil }
        if let meridiem {
            guard (1...12).contains(hour) else { return nil }
            return (hour % 12 + (meridiem == "pm" ? 12 : 0), minute)
        }
        // A bare number is not a time; "15:30" is.
        guard parts.count == 2, (0..<24).contains(hour) else { return nil }
        return (hour, minute)
    }

    // MARK: Dates

    func untilOrSince(_ text: String) -> Answer? {
        for (lead, future) in [("days until ", true), ("days till ", true), ("days to ", true), ("days since ", false)] where text.hasPrefix(lead) {
            guard let date = day(String(text.dropFirst(lead.count))) else { return nil }
            let days = dayCount(from: today, to: date)
            let shown = future ? days : -days
            return Answer(text: "\(Self.days(shown)) \(future ? "until" : "since") \(format(date, zone: calendar.timeZone, "EEE, MMM d, yyyy"))", copy: String(shown))
        }
        return nil
    }

    func arithmetic(_ text: String) -> Answer? {
        // "in 30 days"
        if text.hasPrefix("in "), let offset = duration(String(text.dropFirst(3))),
           let date = calendar.date(byAdding: offset.unit, value: offset.amount, to: today) {
            return dayAnswer(date)
        }
        for op in [" + ", " - "] {
            guard let range = text.range(of: op, options: .backwards) else { continue }
            let left = String(text[..<range.lowerBound])
            let right = String(text[range.upperBound...])
            guard let start = day(left) else { continue }
            if let offset = duration(right) {
                let sign = op == " + " ? 1 : -1
                guard let date = calendar.date(byAdding: offset.unit, value: sign * offset.amount, to: start) else { return nil }
                return dayAnswer(date)
            }
            if op == " - ", let end = day(right) {
                let days = dayCount(from: end, to: start)
                return Answer(text: Self.days(days), copy: String(days))
            }
        }
        if ["today", "tomorrow", "yesterday"].contains(text), let date = day(text) { return dayAnswer(date) }
        return nil
    }

    func dayAnswer(_ date: Date) -> Answer {
        let shown = format(date, zone: calendar.timeZone, "EEE, MMM d, yyyy")
        let iso = format(date, zone: calendar.timeZone, "yyyy-MM-dd")
        let days = dayCount(from: today, to: date)
        let relative = days == 0 ? "today" : days > 0 ? "in \(Self.days(days))" : "\(Self.days(-days)) ago"
        return Answer(text: "\(shown) (\(relative))", copy: iso)
    }

    static func days(_ count: Int) -> String {
        let base = "\(count) day\(abs(count) == 1 ? "" : "s")"
        guard abs(count) >= 14 else { return base }
        let weeks = abs(count) / 7, rest = abs(count) % 7
        return base + " · \(weeks) weeks" + (rest > 0 ? " \(rest) day\(rest == 1 ? "" : "s")" : "")
    }

    var today: Date { calendar.startOfDay(for: now) }

    func dayCount(from a: Date, to b: Date) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: a), to: calendar.startOfDay(for: b)).day ?? 0
    }

    /// "30 days", "2 weeks", "1 month", "3 years".
    func duration(_ text: String) -> (amount: Int, unit: Calendar.Component)? {
        let words = text.split(separator: " ")
        guard words.count == 2, let amount = Int(words[0]) else { return nil }
        switch words[1] {
        case "day", "days", "d": return (amount, .day)
        case "week", "weeks", "w", "wk", "wks": return (amount * 7, .day)
        case "month", "months", "mo": return (amount, .month)
        case "year", "years", "y", "yr", "yrs": return (amount, .year)
        default: return nil
        }
    }

    static let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// "today", "tomorrow", "2026-12-25", "dec 25", "december 25 2027", "25 dec".
    /// A month and day without a year means the next one.
    func day(_ text: String) -> Date? {
        let text = text.replacingOccurrences(of: ",", with: " ").trimmingCharacters(in: .whitespaces)
        switch text {
        case "today", "now": return today
        case "tomorrow": return calendar.date(byAdding: .day, value: 1, to: today)
        case "yesterday": return calendar.date(byAdding: .day, value: -1, to: today)
        default: break
        }
        let iso = text.split(separator: "-")
        if iso.count == 3, let y = Int(iso[0]), let m = Int(iso[1]), let d = Int(iso[2]), y > 999 {
            return calendar.date(from: DateComponents(year: y, month: m, day: d))
        }
        let words = text.split(separator: " ").map(String.init)
        guard words.count == 2 || words.count == 3 else { return nil }
        var month: Int?
        var dayNumber: Int?
        for word in words.prefix(2) {
            if let n = Int(word) { dayNumber = n } else if let m = Self.months.firstIndex(where: { word.hasPrefix($0) }) { month = m + 1 }
        }
        guard let month, let dayNumber, (1...31).contains(dayNumber) else { return nil }
        if words.count == 3 {
            guard let year = Int(words[2]) else { return nil }
            return calendar.date(from: DateComponents(year: year, month: month, day: dayNumber))
        }
        let year = calendar.component(.year, from: today)
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: dayNumber)) else { return nil }
        return date < today ? calendar.date(byAdding: .year, value: 1, to: date) : date
    }

    func splitConversion(_ text: String) -> (String, String)? {
        for word in [" in ", " to ", " as "] {
            if let range = text.range(of: word, options: .backwards) {
                let left = String(text[..<range.lowerBound]).trimmingCharacters(in: .whitespaces)
                let right = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                if !left.isEmpty, !right.isEmpty { return (left, right) }
            }
        }
        return nil
    }

    func format(_ date: Date, zone: TimeZone, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
