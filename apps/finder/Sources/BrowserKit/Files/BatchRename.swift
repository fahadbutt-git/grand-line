import Foundation

/// Rename N Items (Finder's sheet for several selected items): replace text,
/// add text or format with numbers, plus a regular expression mode and case
/// changes, with every new name previewed before anything is renamed. The
/// extension is kept unless asked to change it too. FileKit's `renameItems`
/// then renames them all as one task that Undo reverses at once.
public struct BatchRename: Equatable, Sendable {
    public enum Mode: String, CaseIterable, Sendable {
        case replace, add, format, regex

        public var title: String {
            switch self {
            case .replace: return "Replace Text"
            case .add: return "Add Text"
            case .format: return "Format"
            case .regex: return "Regular Expression"
            }
        }
    }

    public enum Position: String, CaseIterable, Sendable {
        case before, after

        public var title: String { self == .before ? "before name" : "after name" }
    }

    /// Finder's three formats: "Photo1", "Photo00001", "Photo 2026-10-31".
    public enum Format: String, CaseIterable, Sendable {
        case index, counter, date

        public var title: String {
            switch self {
            case .index: return "Name and Index"
            case .counter: return "Name and Counter"
            case .date: return "Name and Date"
            }
        }
    }

    public enum TextCase: String, CaseIterable, Sendable {
        case unchanged, lower, upper, title

        public var title: String {
            switch self {
            case .unchanged: return "Keep case"
            case .lower: return "lowercase"
            case .upper: return "UPPERCASE"
            case .title: return "Title Case"
            }
        }
    }

    /// One row of the preview.
    public struct Row: Equatable, Sendable {
        public let item: URL
        public let old: String
        public let new: String
        /// Why this name cannot be used, nil when it can.
        public let problem: String?

        public var changes: Bool { old != new }
    }

    public var mode: Mode = .replace
    // Replace Text and Regular Expression
    public var find = ""
    public var replacement = ""
    public var matchCase = false
    // Add Text
    public var addText = ""
    public var addPosition: Position = .after
    // Format
    public var format: Format = .index
    public var formatPosition: Position = .after
    public var customFormat = ""
    public var startAt = 1
    // Every mode
    public var textCase: TextCase = .unchanged
    public var includeExtension = false

    public init() {}

    /// Why the regular expression cannot be used, nil when it can (or the mode is another).
    public var patternProblem: String? {
        guard mode == .regex, !find.isEmpty else { return nil }
        do {
            _ = try NSRegularExpression(pattern: find)
            return nil
        } catch {
            return "The pattern is not a valid regular expression."
        }
    }

    /// The new name for the `index`th item (0 based) of the batch.
    public func newName(for name: String, index: Int, date: Date = Date()) -> String {
        let (stem, ext) = split(name)
        var changed = stem
        switch mode {
        case .replace:
            if !find.isEmpty {
                changed = changed.replacingOccurrences(of: find, with: replacement, options: matchCase ? [] : [.caseInsensitive])
            }
        case .regex:
            if !find.isEmpty, let expression = try? NSRegularExpression(pattern: find, options: matchCase ? [] : [.caseInsensitive]) {
                let range = NSRange(changed.startIndex..., in: changed)
                changed = expression.stringByReplacingMatches(in: changed, options: [], range: range, withTemplate: replacement)
            }
        case .add:
            changed = addPosition == .before ? addText + changed : changed + addText
        case .format:
            let number = startAt + index
            let mark: String
            switch format {
            case .index: mark = String(number)
            case .counter: mark = String(format: "%05d", number)
            case .date: mark = Self.dateText(date)
            }
            let separator = format == .date && !customFormat.isEmpty ? " " : ""
            changed = formatPosition == .after ? customFormat + separator + mark : mark + separator + customFormat
        }
        changed = apply(textCase, to: changed)
        return ext.isEmpty ? changed : changed + "." + ext
    }

    /// Every item's new name, with the problems that would stop the rename:
    /// an empty or invalid name, two items given one name, or a name already
    /// used by another item in the folder. `existing` lists a folder's names.
    public func preview(_ items: [URL], date: Date = Date(), existing: (URL) -> Set<String>) -> [Row] {
        let names = items.enumerated().map { newName(for: $0.element.lastPathComponent, index: $0.offset, date: date) }
        var counts: [String: Int] = [:]
        for (item, name) in zip(items, names) { counts[key(item.deletingLastPathComponent(), name), default: 0] += 1 }
        let leaving = Set(items.map { key($0.deletingLastPathComponent(), $0.lastPathComponent) })
        var folders: [URL: Set<String>] = [:]
        return zip(items, names).map { item, name in
            let folder = item.deletingLastPathComponent()
            if folders[folder] == nil { folders[folder] = Set(existing(folder).map { $0.lowercased() }) }
            let old = item.lastPathComponent
            var problem: String?
            if let reason = Self.invalid(name) {
                problem = reason
            } else if counts[key(folder, name), default: 0] > 1 {
                problem = "Another item gets this name."
            } else if name.lowercased() != old.lowercased(), folders[folder]?.contains(name.lowercased()) == true,
                      !leaving.contains(key(folder, name)) {
                problem = "An item with this name is already here."
            }
            return Row(item: item, old: old, new: name, problem: problem)
        }
    }

    /// Whether the preview can be applied: something changes and nothing is wrong.
    public static func canApply(_ rows: [Row]) -> Bool {
        rows.contains(where: \.changes) && rows.allSatisfy { $0.problem == nil }
    }

    static func invalid(_ name: String) -> String? {
        if name.isEmpty || name == "." || name == ".." { return "The name is empty." }
        if name.contains("/") || name.contains(":") || name.contains("\0") { return "Names cannot hold \u{201C}/\u{201D} or \u{201C}:\u{201D}." }
        if name.utf8.count > 255 { return "The name is too long." }
        return nil
    }

    func key(_ folder: URL, _ name: String) -> String {
        folder.standardizedFileURL.path + "/" + name.lowercased()
    }

    func split(_ name: String) -> (String, String) {
        guard !includeExtension else { return (name, "") }
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        if ext.isEmpty || stem.isEmpty || ext.contains(" ") { return (name, "") }
        return (stem, ext)
    }

    func apply(_ textCase: TextCase, to text: String) -> String {
        switch textCase {
        case .unchanged: return text
        case .lower: return text.lowercased()
        case .upper: return text.uppercased()
        case .title: return text.capitalized
        }
    }

    static func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
