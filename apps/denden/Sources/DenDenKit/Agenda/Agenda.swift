import Foundation

/// A calendar event, copied out of EventKit so the choosing and ordering can
/// be tested without it.
public struct AgendaEvent: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var calendar: String

    public init(id: String, title: String, start: Date, end: Date, isAllDay: Bool = false, calendar: String = "") {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.calendar = calendar
    }
}

/// A reminder, copied out of EventKit.
public struct AgendaReminder: Equatable, Sendable, Identifiable {
    public var id: String
    public var title: String
    /// nil for a reminder with a due day but no time.
    public var due: Date?
    public var dueDay: Date?
    public var priority: Int
    public var isCompleted: Bool

    public init(id: String, title: String, due: Date? = nil, dueDay: Date? = nil, priority: Int = 0, isCompleted: Bool = false) {
        self.id = id
        self.title = title
        self.due = due
        self.dueDay = dueDay
        self.priority = priority
        self.isCompleted = isCompleted
    }
}

public enum Agenda {
    /// Midnight today to midnight tomorrow.
    public static func today(_ now: Date, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86400)
        return DateInterval(start: start, end: end)
    }

    /// Today's events still worth showing: all-day ones first, then timed
    /// events that have not ended, soonest first.
    public static func upcoming(_ events: [AgendaEvent], now: Date, calendar: Calendar = .current, limit: Int = 4) -> [AgendaEvent] {
        let day = today(now, calendar: calendar)
        let todays = events.filter { $0.start < day.end && $0.end > day.start }
        let allDay = todays.filter(\.isAllDay).sorted { $0.title < $1.title }
        let timed = todays.filter { !$0.isAllDay && $0.end > now }.sorted {
            $0.start != $1.start ? $0.start < $1.start : $0.title < $1.title
        }
        return Array((allDay + timed).prefix(limit))
    }

    /// True for the event happening now.
    public static func isCurrent(_ e: AgendaEvent, now: Date) -> Bool {
        !e.isAllDay && e.start <= now && e.end > now
    }

    /// Open reminders due today or overdue: timed ones by time, then the rest
    /// by priority (1 is high in EventKit, 0 is none).
    public static func dueToday(_ reminders: [AgendaReminder], now: Date, calendar: Calendar = .current, limit: Int = 5) -> [AgendaReminder] {
        let end = today(now, calendar: calendar).end
        let due = reminders.filter { r in
            guard !r.isCompleted else { return false }
            if let d = r.due { return d < end }
            if let day = r.dueDay { return day < end }
            return false
        }
        func rank(_ p: Int) -> Int { p == 0 ? 10 : p }
        let sorted = due.sorted { a, b in
            let da = a.due ?? a.dueDay ?? .distantFuture
            let db = b.due ?? b.dueDay ?? .distantFuture
            if da != db { return da < db }
            if rank(a.priority) != rank(b.priority) { return rank(a.priority) < rank(b.priority) }
            return a.title < b.title
        }
        return Array(sorted.prefix(limit))
    }

    /// "9:30", or "All day".
    public static func timeLabel(_ e: AgendaEvent, calendar: Calendar = .current, locale: Locale = .current) -> String {
        if e.isAllDay { return "All day" }
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = locale
        f.setLocalizedDateFormatFromTemplate("jmm")
        return f.string(from: e.start)
    }
}
