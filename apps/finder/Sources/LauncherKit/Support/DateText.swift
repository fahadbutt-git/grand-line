import Foundation

/// Dates as rows show them, and strftime formats as Espanso writes them.
public enum DateText {
    /// "today", "yesterday", "3 days", "2 weeks", "5 months", "2 years".
    public static func relative(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0
        switch days {
        case ..<0: return "soon"
        case 0: return "today"
        case 1: return "yesterday"
        case 2..<7: return "\(days) days"
        case 7..<31: return plural(days / 7, "week")
        case 31..<365: return plural(max(1, days / 30), "month")
        default: return plural(days / 365, "year")
        }
    }

    static func plural(_ count: Int, _ unit: String) -> String {
        "\(count) \(unit)\(count == 1 ? "" : "s")"
    }

    /// The strftime directives Espanso's date variables use: %Y %y %m %d %e %-d
    /// %-m %B %b %A %a %H %I %-I %M %S %p %j %%.
    public static func strftime(_ format: String, _ date: Date, calendar: Calendar = .current) -> String {
        var calendar = calendar
        calendar.locale = Locale(identifier: "en_US_POSIX")
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
        let year = parts.year ?? 0, month = parts.month ?? 1, day = parts.day ?? 1
        let hour = parts.hour ?? 0, minute = parts.minute ?? 0, second = parts.second ?? 0
        let weekday = (parts.weekday ?? 1) - 1
        let hour12 = hour % 12 == 0 ? 12 : hour % 12
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let months = calendar.monthSymbols, shortMonths = calendar.shortMonthSymbols
        let days = calendar.weekdaySymbols, shortDays = calendar.shortWeekdaySymbols
        func two(_ n: Int) -> String { n < 10 ? "0\(n)" : "\(n)" }

        var out = ""
        var chars = Array(format)[...]
        while let c = chars.popFirst() {
            guard c == "%", let next = chars.popFirst() else { out.append(c); continue }
            var directive = next
            var unpadded = false
            if directive == "-", let after = chars.popFirst() {
                unpadded = true
                directive = after
            }
            switch directive {
            case "Y": out += "\(year)"
            case "y": out += two(year % 100)
            case "m": out += unpadded ? "\(month)" : two(month)
            case "d": out += unpadded ? "\(day)" : two(day)
            case "e": out += day < 10 ? " \(day)" : "\(day)"
            case "B": out += months[month - 1]
            case "b", "h": out += shortMonths[month - 1]
            case "A": out += days[weekday]
            case "a": out += shortDays[weekday]
            case "H": out += unpadded ? "\(hour)" : two(hour)
            case "I": out += unpadded ? "\(hour12)" : two(hour12)
            case "M": out += two(minute)
            case "S": out += two(second)
            case "p": out += hour < 12 ? "AM" : "PM"
            case "j": out += unpadded ? "\(dayOfYear)" : String(format: "%03d", dayOfYear)
            case "%": out += "%"
            default: out += "%" + (unpadded ? "-" : "") + String(directive)
            }
        }
        return out
    }
}
