import Foundation

/// Places and abbreviations to time zones: a short list of names people use,
/// then the city part of any IANA identifier ("new york" → America/New_York).
public enum TimeZones {
    static let names: [String: String] = [
        "utc": "UTC", "gmt": "GMT", "z": "UTC",
        "et": "America/New_York", "est": "America/New_York", "edt": "America/New_York", "eastern": "America/New_York",
        "ct": "America/Chicago", "cst": "America/Chicago", "cdt": "America/Chicago", "central": "America/Chicago",
        "mt": "America/Denver", "mst": "America/Denver", "mdt": "America/Denver", "mountain": "America/Denver",
        "pt": "America/Los_Angeles", "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "pacific": "America/Los_Angeles",
        "at": "America/Halifax", "ast": "America/Halifax", "adt": "America/Halifax", "atlantic": "America/Halifax",
        "nt": "America/St_Johns", "nst": "America/St_Johns", "ndt": "America/St_Johns", "newfoundland": "America/St_Johns",
        "bst": "Europe/London", "uk": "Europe/London", "cet": "Europe/Paris", "cest": "Europe/Paris",
        "eet": "Europe/Athens", "ist": "Asia/Kolkata", "pkt": "Asia/Karachi", "jst": "Asia/Tokyo", "kst": "Asia/Seoul",
        "aest": "Australia/Sydney", "aedt": "Australia/Sydney", "nzst": "Pacific/Auckland", "hkt": "Asia/Hong_Kong",
        "ottawa": "America/Toronto", "montreal": "America/Toronto", "quebec": "America/Toronto",
        "calgary": "America/Edmonton", "victoria": "America/Vancouver", "saskatoon": "America/Regina",
        "nyc": "America/New_York", "boston": "America/New_York", "washington": "America/New_York", "miami": "America/New_York",
        "sf": "America/Los_Angeles", "san francisco": "America/Los_Angeles", "la": "America/Los_Angeles", "seattle": "America/Los_Angeles",
        "houston": "America/Chicago", "dallas": "America/Chicago",
        "delhi": "Asia/Kolkata", "new delhi": "Asia/Kolkata", "mumbai": "Asia/Kolkata", "bangalore": "Asia/Kolkata",
        "lahore": "Asia/Karachi", "islamabad": "Asia/Karachi", "beijing": "Asia/Shanghai", "china": "Asia/Shanghai",
        "japan": "Asia/Tokyo", "korea": "Asia/Seoul", "uae": "Asia/Dubai", "abu dhabi": "Asia/Dubai", "riyadh": "Asia/Riyadh",
        "mecca": "Asia/Riyadh", "makkah": "Asia/Riyadh", "germany": "Europe/Berlin", "france": "Europe/Paris",
        "italy": "Europe/Rome", "spain": "Europe/Madrid", "india": "Asia/Kolkata", "pakistan": "Asia/Karachi",
    ]

    public static func zone(_ text: String) -> TimeZone? {
        let key = text.lowercased().trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty else { return nil }
        if let id = names[key] { return TimeZone(identifier: id) }
        let underscored = key.replacingOccurrences(of: " ", with: "_")
        for id in TimeZone.knownTimeZoneIdentifiers {
            let city = id.split(separator: "/").last.map { $0.lowercased() } ?? ""
            if city == underscored || id.lowercased() == underscored { return TimeZone(identifier: id) }
        }
        return nil
    }

    /// The place as written, capitalised: "new york" → "New York".
    public static func label(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        return trimmed.count <= 4 ? trimmed.uppercased() : trimmed.capitalized
    }
}
