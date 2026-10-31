import Foundation

// Format 1 of the theme files (DESIGN.md, "Theme format"): reading a file
// with its EXTENDS parents, and the checker that fills the defaults and
// reports bad values and weak contrast. This file is the same in ThemeKit
// and IcebergKit (tests/unit.sh compares the two) and reads themes exactly
// as lib/templates.sh does for the shell; tests/fixtures/theme-resolved.txt
// holds what all of them must agree on.

/// A problem in a theme file, as `theme check` prints it.
public struct ThemeDiagnostic: Sendable, Equatable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }

    public let severity: Severity
    /// The file's name, such as "harbour-light.theme" (a parent's, when the key came from it).
    public let file: String
    /// From 1; nil when the problem is the file as a whole, such as a missing key.
    public let line: Int?
    public let message: String

    public init(severity: Severity, file: String, line: Int?, message: String) {
        self.severity = severity
        self.file = file
        self.line = line
        self.message = message
    }

    public var description: String {
        "\(file)\(line.map { ":\($0)" } ?? ""): \(severity.rawValue): \(message)"
    }
}

/// One key as a file sets it.
public struct ThemeEntry: Sendable, Equatable {
    public let value: String
    public let file: String
    /// From 1; 0 for a value that came from no file.
    public let line: Int

    public init(value: String, file: String, line: Int) {
        self.value = value
        self.file = file
        self.line = line
    }
}

/// A theme's keys after following EXTENDS: each key from the nearest file
/// that sets it. EXTENDS itself is not kept.
public struct ThemeSource: Sendable, Equatable {
    public var entries: [String: ThemeEntry]
    /// Problems found while reading: lines that are not KEY=value, loops, missing parents.
    public var diagnostics: [ThemeDiagnostic]
    /// The name of the file the theme was read from.
    public var file: String

    public init(entries: [String: ThemeEntry], diagnostics: [ThemeDiagnostic] = [], file: String) {
        self.entries = entries
        self.diagnostics = diagnostics
        self.file = file
    }

    /// Keys from somewhere other than a file, such as a built-in theme.
    public init(values: [String: String], file: String) {
        var entries: [String: ThemeEntry] = [:]
        for (key, value) in values where key != "EXTENDS" { entries[key] = ThemeEntry(value: value, file: file, line: 0) }
        self.init(entries: entries, file: file)
    }

    /// The most themes one EXTENDS chain may hold.
    public static let maxDepth = 8

    /// The theme file at `url` with its parents from the same folder, or nil
    /// when the file cannot be read.
    public static func resolve(url: URL) -> ThemeSource? {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return resolve(text: text, file: url.lastPathComponent, folder: url.deletingLastPathComponent())
    }

    /// `text`, the file named `file`, with its parents read from `folder`.
    public static func resolve(text: String, file: String, folder: URL?) -> ThemeSource {
        var diagnostics: [ThemeDiagnostic] = []
        var chain: [[String: ThemeEntry]] = []
        var seen: Set<String> = [Self.themeName(file)]
        let first = parse(text, file: file)
        diagnostics += first.diagnostics
        chain.append(first.entries)
        var parent = first.entries["EXTENDS"]
        while let link = parent {
            let name = link.value
            func fail(_ message: String) {
                diagnostics.append(ThemeDiagnostic(severity: .error, file: link.file, line: link.line, message: message))
            }
            guard ThemeSpec.isName(name) else { fail("EXTENDS=\(name) must be the name of a theme in the same folder"); break }
            guard chain.count < maxDepth else { fail("EXTENDS goes more than \(maxDepth) themes deep"); break }
            guard !seen.contains(name) else { fail("EXTENDS=\(name) leads back to \(name) (a loop)"); break }
            seen.insert(name)
            guard let folder,
                  let parentText = try? String(contentsOf: folder.appendingPathComponent(name + ".theme"), encoding: .utf8)
            else { fail("EXTENDS=\(name) names no theme (\(name).theme is missing)"); break }
            let read = parse(parentText, file: name + ".theme")
            diagnostics += read.diagnostics
            chain.append(read.entries)
            parent = read.entries["EXTENDS"]
        }
        var merged: [String: ThemeEntry] = [:]
        for entries in chain.reversed() {
            for (key, entry) in entries where key != "EXTENDS" { merged[key] = entry }
        }
        return ThemeSource(entries: merged, diagnostics: diagnostics, file: file)
    }

    /// One file's KEY=value lines, without following EXTENDS.
    public static func parse(_ text: String, file: String) -> (entries: [String: ThemeEntry], diagnostics: [ThemeDiagnostic]) {
        var entries: [String: ThemeEntry] = [:]
        var diagnostics: [ThemeDiagnostic] = []
        func warn(_ line: Int, _ message: String) {
            diagnostics.append(ThemeDiagnostic(severity: .warning, file: file, line: line, message: message))
        }
        var number = 0
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" || $0 == "\r\n" }) {
            number += 1
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasSuffix("\r") { line = String(line.dropLast()).trimmingCharacters(in: .whitespaces) }
            if line.isEmpty || line.hasPrefix("#") { continue }
            for prefix in ["export ", "export\t"] where line.hasPrefix(prefix) {
                line = String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
            }
            let equals = line.firstIndex(of: "=")
            let key = equals.map { line[..<$0].trimmingCharacters(in: .whitespaces) } ?? ""
            guard let equals, ThemeSpec.isKeyName(key) else {
                warn(number, "not a KEY=value line (keys are upper case); ignored")
                continue
            }
            var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'" {
                let rest = value.dropFirst()
                if let end = rest.firstIndex(of: quote) {
                    value = String(rest[..<end])
                } else {
                    warn(number, "\(key) has no closing quote")
                    value = String(rest)
                }
            } else {
                value = Self.withoutComment(value)
            }
            if entries[key] != nil { warn(number, "\(key) is set twice in this file; this line wins") }
            entries[key] = ThemeEntry(value: value, file: file, line: number)
        }
        return (entries, diagnostics)
    }

    /// "value  # note" without the note: a # after a space or tab starts one.
    static func withoutComment(_ value: String) -> String {
        var previous: Character = "#"
        for index in value.indices {
            let character = value[index]
            if character == "#", previous == " " || previous == "\t" {
                return String(value[..<index]).trimmingCharacters(in: .whitespaces)
            }
            previous = character
        }
        return value
    }

    static func themeName(_ file: String) -> String {
        file.hasSuffix(".theme") ? String(file.dropLast(6)) : file
    }
}

/// What the checker made of a theme: every value cleaned and the defaults
/// filled in, and what it found wrong.
public struct ThemeValidation: Sendable, Equatable {
    public var values: [String: String]
    public var diagnostics: [ThemeDiagnostic]

    public init(values: [String: String], diagnostics: [ThemeDiagnostic]) {
        self.values = values
        self.diagnostics = diagnostics
    }

    public var errors: [ThemeDiagnostic] { diagnostics.filter { $0.severity == .error } }
    public var warnings: [ThemeDiagnostic] { diagnostics.filter { $0.severity == .warning } }
}

/// The keys of format 1, their allowed values and defaults (DESIGN.md, "Theme format").
public enum ThemeSpec {
    /// The newest format this version reads.
    public static let format = 1

    /// Posted (distributed) by `theme set` and `theme apply` once the new theme is in place.
    public static let changedNotification = "com.grandline.theme.changed"

    /// Keys every theme must have, itself or through EXTENDS.
    public static let requiredKeys = ["FORMAT", "LABEL", "MODE", "TERM_BG", "TERM_FG", "PALETTE"]

    /// Keys with a fixed set of values.
    public static let choices: [String: [String]] = [
        "MODE": ["dark", "light"],
        "ICON_STYLE": ["line", "solid", "mono"],
        "KIND_STYLE": ["tag", "dot", "solid", "text"],
        "UI_DENSITY": ["compact", "regular", "comfortable"],
        "UI_MOTION": ["full", "reduced"],
    ]

    /// Keys holding a whole number, and its range.
    public static let numbers: [String: ClosedRange<Int>] = [
        "FONT_SIZE": 9...24, "RADIUS_WINDOW": 0...32, "RADIUS_CHIP": 0...16, "SPACING_UNIT": 2...16,
    ]

    /// Defaults that do not depend on the theme's colours. UI_DENSITY has
    /// none: without it each app keeps its own choice.
    public static let fixedDefaults: [String: String] = [
        "ACCENT": "-1", "NVIM": "vscode", "ICON_STYLE": "line", "KIND_STYLE": "tag",
        "FONT_UI": "SF Pro", "FONT_MONO": "SF Mono", "FONT_SIZE": "13",
        "RADIUS_WINDOW": "10", "RADIUS_CHIP": "5", "SPACING_UNIT": "4", "UI_MOTION": "full",
    ]

    /// Each KIND_ colour's default, as KIND:KEY: another key, or COLORn for a PALETTE entry.
    static let kindDefaults = [
        "FOLDER:ACCENT_HEX", "DOCUMENT:COLOR4", "PDF:COLOR1", "PRESENTATION:COLOR3", "SPREADSHEET:COLOR2",
        "IMAGE:COLOR5", "VIDEO:COLOR13", "CODE:COLOR11", "ARCHIVE:COLOR9", "TEXT:MUTED",
    ]

    static let colourKeys: Set<String> = [
        "TERM_BG", "TERM_FG", "TERM_CURSOR", "TERM_SELECTION", "ACCENT_HEX", "MUTED", "BG_LIGHTER", "BG_DARKER",
        "HIGHLIGHT", "SIDEBAR", "FIELD", "LINE", "NOTCH_PANEL", "NOTCH_CARD", "NOTCH_LINE",
        "ICON_TILE", "ICON_INK", "ICON_ACCENT", "ICON_SOFT", "ICON_FILES", "ICON_SEARCH", "ICON_NOTCH",
    ]

    /// Whether a key holds one colour (PALETTE holds sixteen and is not one).
    public static func isColourKey(_ key: String) -> Bool {
        if colourKeys.contains(key) { return true }
        if key.hasPrefix("KIND_"), key != "KIND_STYLE" {
            let rest = key.dropFirst(5)
            return !rest.isEmpty && rest.allSatisfy { $0.isASCII && $0.isUppercase }
        }
        if key.hasPrefix("COLOR_") {
            let rest = key.dropFirst(6)
            return !rest.isEmpty && rest.allSatisfy { $0.isASCII && ($0.isUppercase || $0.isNumber || $0 == "_") }
        }
        if key.hasPrefix("COLOR") {
            let rest = key.dropFirst(5)
            return !rest.isEmpty && rest.allSatisfy { $0.isASCII && $0.isNumber }
        }
        return false
    }

    static func isPaletteSlot(_ key: String) -> Bool {
        guard key.hasPrefix("COLOR"), let n = Int(key.dropFirst(5)), key.count <= 7 else { return false }
        return (0...15).contains(n) && String(n) == key.dropFirst(5)
    }

    /// Upper-case letters, digits and _, not starting with a digit.
    static func isKeyName(_ key: String) -> Bool {
        guard let first = key.first, first == "_" || (first.isASCII && first.isUppercase) else { return false }
        return key.allSatisfy { $0 == "_" || ($0.isASCII && ($0.isUppercase || $0.isNumber)) }
    }

    /// A theme or family name: lower-case letters, digits, - and _.
    static func isName(_ name: String) -> Bool {
        guard let first = name.first, first.isASCII, first.isLowercase || first.isNumber else { return false }
        return name.allSatisfy { $0.isASCII && ($0.isLowercase || $0.isNumber || $0 == "-" || $0 == "_") }
    }

    /// Checks every value and fills the defaults. With `fallback`, a required
    /// key that is missing or wrong takes the fallback's value (still reported),
    /// so a broken theme shows as its base theme rather than not at all.
    public static func validate(_ source: ThemeSource, fallback: [String: String]? = nil) -> ThemeValidation {
        var values: [String: String] = [:]
        var diagnostics = source.diagnostics
        func report(_ severity: ThemeDiagnostic.Severity, _ key: String?, _ message: String) {
            let entry = key.flatMap { source.entries[$0] }
            diagnostics.append(ThemeDiagnostic(severity: severity, file: entry?.file ?? source.file,
                                               line: entry.flatMap { $0.line > 0 ? $0.line : nil }, message: message))
        }

        let ordered = source.entries.sorted { a, b in
            (a.value.file, a.value.line, a.key) < (b.value.file, b.value.line, b.key)
        }
        for (key, entry) in ordered {
            let value = entry.value
            if key == "PALETTE" {
                let parts = value.split(whereSeparator: { $0 == " " || $0 == "\t" })
                    .map { $0.hasPrefix("#") ? String($0.dropFirst()) : String($0) }
                let bad = parts.filter { Hex(hex: $0) == nil }
                if parts.count != 16 {
                    report(.error, key, "PALETTE has \(parts.count) colours; it needs 16")
                } else if !bad.isEmpty {
                    report(.error, key, "PALETTE has colours that are not six-digit hex: " + bad.joined(separator: " "))
                } else {
                    values[key] = parts.map { $0.lowercased() }.joined(separator: " ")
                }
            } else if isPaletteSlot(key) {
                report(.warning, key, "\(key) comes from PALETTE; this line is ignored")
            } else if isColourKey(key) {
                if let colour = Hex(hex: value.hasPrefix("#") ? String(value.dropFirst()) : value) {
                    values[key] = colour.hex
                } else {
                    report(.error, key, "\(key)=\(value) is not a six-digit hex colour")
                }
            } else if let allowed = choices[key] {
                if allowed.contains(value.lowercased()) { values[key] = value.lowercased() }
                else { report(.error, key, "\(key)=\(value) must be one of: " + allowed.joined(separator: " ")) }
            } else if let range = numbers[key] {
                if value.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(value), range.contains(n) { values[key] = value }
                else { report(.error, key, "\(key)=\(value) must be a whole number from \(range.lowerBound) to \(range.upperBound)") }
            } else {
                switch key {
                case "FORMAT":
                    let n = value.allSatisfy({ $0.isASCII && $0.isNumber }) ? Int(value) : nil
                    if let n, n >= 1, n <= format { values[key] = value }
                    else if let n, n > format { report(.error, key, "FORMAT=\(value) is newer than this version reads (\(format)); update the package") }
                    else { report(.error, key, "FORMAT=\(value) must be a format number (\(format))") }
                case "ACCENT":
                    if ["-1", "0", "1", "2", "3", "4", "5", "6", "multicolor"].contains(value) { values[key] = value }
                    else { report(.error, key, "ACCENT=\(value) must be -1 to 6 or multicolor") }
                case "LABEL":
                    if value.isEmpty { report(.error, key, "LABEL is empty") } else { values[key] = value }
                case "FAMILY", "NVIM":
                    if isName(value) { values[key] = value } else { report(.error, key, "\(key)=\(value) must be a lower-case name") }
                case "BACKGROUND":
                    if value.isEmpty || value.contains("/") || value.hasPrefix(".") {
                        report(.error, key, "BACKGROUND=\(value) must be a file name in backgrounds/")
                    } else { values[key] = value }
                case "FONT_UI", "FONT_MONO":
                    if value.isEmpty { report(.error, key, "\(key) is empty") } else { values[key] = value }
                default:
                    values[key] = value
                }
            }
        }

        for key in requiredKeys where source.entries[key] == nil {
            if key == "FORMAT" { report(.warning, nil, "FORMAT is missing; read as format \(format)") }
            else { report(.error, nil, "\(key) is missing") }
        }
        if let fallback {
            for key in requiredKeys where values[key] == nil { values[key] = fallback[key] }
        }

        // Defaults, in the order lib/templates.sh fills them.
        func fill(_ key: String, _ value: String?) {
            if values[key] == nil, let value, !value.isEmpty { values[key] = value }
        }
        let palette = (values["PALETTE"] ?? "").split(separator: " ").map(String.init)
        func lookup(_ key: String) -> String? {
            if isPaletteSlot(key), let n = Int(key.dropFirst(5)) { return n < palette.count ? palette[n] : nil }
            return values[key]
        }
        let isDark = values["MODE"].map { $0 == "dark" } ?? (values["TERM_BG"].flatMap(Hex.init(hex:)).map { $0.luminance < 0.4 } ?? false)
        fill("FORMAT", String(format))
        fill("ACCENT_HEX", values["HIGHLIGHT"] ?? lookup("COLOR4"))
        fill("HIGHLIGHT", values["ACCENT_HEX"])
        fill("TERM_CURSOR", values["ACCENT_HEX"])
        if let background = values["TERM_BG"].flatMap(Hex.init(hex:)) {
            if let accent = values["ACCENT_HEX"].flatMap(Hex.init(hex:)) {
                fill("TERM_SELECTION", background.mixed(with: accent, 0.25).hex)
            }
            if let text = values["TERM_FG"].flatMap(Hex.init(hex:)) {
                fill("MUTED", text.mixed(with: background, 0.45).hex)
                fill("BG_LIGHTER", background.mixed(with: text, 0.04).hex)
                fill("BG_DARKER", (isDark ? background.mixed(with: Hex(red: 0, green: 0, blue: 0), 0.3) : background.mixed(with: text, 0.1)).hex)
            }
        }
        for pair in kindDefaults {
            let parts = pair.split(separator: ":").map(String.init)
            fill("KIND_" + parts[0], lookup(parts[1]))
        }
        fill("BACKGROUND", isDark ? "graphite.jpg" : "daylight.jpg")
        for (key, value) in fixedDefaults { fill(key, value) }

        // Contrast: text 4.5:1 and secondary text 3:1 on the window and the sidebar.
        let sidebar = values["SIDEBAR"] != nil ? "SIDEBAR" : "BG_LIGHTER"
        for (foreground, surface, ratio) in [("TERM_FG", "TERM_BG", 4.5), ("TERM_FG", sidebar, 4.5),
                                             ("MUTED", "TERM_BG", 3.0), ("MUTED", sidebar, 3.0)] {
            guard let a = values[foreground].flatMap(Hex.init(hex:)), let b = values[surface].flatMap(Hex.init(hex:)) else { continue }
            let measured = a.contrast(with: b)
            if measured < ratio {
                let role = foreground == "MUTED" ? "secondary text" : "text"
                report(.warning, foreground, "\(foreground) #\(a.hex) is \(String(format: "%.2f", measured)):1 on \(surface) #\(b.hex); \(role) needs \(String(format: "%.1f", ratio)):1")
            }
        }
        return ThemeValidation(values: values, diagnostics: diagnostics)
    }

    /// A six-digit sRGB colour, computed the way lib/templates.sh computes it.
    struct Hex: Equatable {
        let red: Double
        let green: Double
        let blue: Double

        init(red: Double, green: Double, blue: Double) {
            self.red = min(max(red, 0), 1)
            self.green = min(max(green, 0), 1)
            self.blue = min(max(blue, 0), 1)
        }

        /// Exactly six hex digits, no "#".
        init?(hex: String) {
            guard hex.count == 6, hex.allSatisfy({ $0.isHexDigit && $0.isASCII }), let v = UInt32(hex, radix: 16) else { return nil }
            self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
        }

        var hex: String {
            [red, green, blue].map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
        }

        func mixed(with other: Hex, _ amount: Double) -> Hex {
            Hex(red: red + (other.red - red) * amount, green: green + (other.green - green) * amount,
                blue: blue + (other.blue - blue) * amount)
        }

        var luminance: Double {
            func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }

        func contrast(with other: Hex) -> Double {
            let (a, b) = (luminance, other.luminance)
            return (max(a, b) + 0.05) / (min(a, b) + 0.05)
        }
    }
}
