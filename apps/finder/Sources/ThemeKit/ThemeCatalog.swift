import Foundation

/// One theme file, read for a preview: its name, its keys and its colours.
public struct ThemeVariant: Sendable, Equatable {
    public let name: String
    public let values: [String: String]
    public let theme: Theme

    public init(name: String, values: [String: String]) {
        self.name = name
        self.values = values
        self.theme = Theme(name: name, values: values)
    }

    public var isDark: Bool { theme.isDark }
}

/// What the Appearance pane offers as one card: a dark and light pair
/// (FAMILY=, or Graphite and Daylight), or a theme on its own.
public struct ThemeFamily: Sendable, Equatable, Identifiable {
    /// The FAMILY= name, "system" for Graphite and Daylight, or the file's name.
    public let id: String
    public let label: String
    public let dark: ThemeVariant?
    public let light: ThemeVariant?
    /// A FAMILY= pair, so `theme set <id>` picks the variant itself.
    public let isFilePair: Bool

    public init(id: String, label: String, dark: ThemeVariant?, light: ThemeVariant?, isFilePair: Bool) {
        self.id = id
        self.label = label
        self.dark = dark
        self.light = light
        self.isFilePair = isFilePair
    }

    public var variants: [ThemeVariant] { [dark, light].compactMap { $0 } }

    /// Both a dark and a light variant, so dark, light and following macOS all apply.
    public var hasPair: Bool { dark != nil && light != nil }

    /// The variant for that appearance, else the one there is.
    public func variant(dark wantsDark: Bool) -> ThemeVariant? {
        wantsDark ? (dark ?? light) : (light ?? dark)
    }

    public func contains(_ name: String) -> Bool {
        variants.contains { $0.name == name }
    }
}

/// Lists the themes in config/themes as families, read the way ThemeKit and
/// `theme list` read them.
public enum ThemeCatalog {
    /// The order of the cards: the paired families, Graphite and Daylight,
    /// then the single themes. Anything else follows by name.
    public static let preferredOrder = ["harbour", "lantern", "signal", "ledger", "atlas", "paper",
                                        ThemeFollow.systemFamily, "nord", "forest"]

    /// Every *.theme file in the folder. With none (a build run before setup),
    /// Graphite and Daylight from `BuiltInThemes`.
    public static func families(in folder: URL) -> [ThemeFamily] {
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        var read: [(name: String, values: [String: String])] = []
        for file in files where file.pathExtension == "theme" {
            if let values = ThemeFile.read(file) { read.append((file.deletingPathExtension().lastPathComponent, values)) }
        }
        if read.isEmpty {
            read = [("graphite", BuiltInThemes.graphite), ("daylight", BuiltInThemes.daylight)]
        }
        return families(files: read)
    }

    /// The families made from (name, keys) pairs, in `preferredOrder`.
    public static func families(files: [(name: String, values: [String: String])]) -> [ThemeFamily] {
        var groups: [String: (dark: ThemeVariant?, light: ThemeVariant?, pair: Bool, label: String?)] = [:]
        for (name, values) in files.sorted(by: { $0.name < $1.name }) {
            let variant = ThemeVariant(name: name, values: values)
            let family = values["FAMILY"]?.trimmingCharacters(in: .whitespaces) ?? ""
            let id: String
            let pair: Bool
            if !family.isEmpty {
                id = family.lowercased()
                pair = true
            } else if ThemeFollow.systemPair.contains(name) {
                id = ThemeFollow.systemFamily
                pair = false
            } else {
                id = name
                pair = false
            }
            var group = groups[id] ?? (dark: nil, light: nil, pair: pair, label: nil)
            if variant.isDark {
                if group.dark == nil { group.dark = variant } else if group.light == nil { group.light = variant }
            } else {
                if group.light == nil { group.light = variant } else if group.dark == nil { group.dark = variant }
            }
            if group.label == nil, !family.isEmpty || id == name { group.label = label(id: id, values: values, isFamily: !family.isEmpty) }
            groups[id] = group
        }
        let all = groups.map { id, group in
            ThemeFamily(id: id, label: id == ThemeFollow.systemFamily ? "Graphite and Daylight" : (group.label ?? id.capitalized),
                        dark: group.dark, light: group.light, isFilePair: group.pair)
        }
        return all.sorted { a, b in
            let x = preferredOrder.firstIndex(of: a.id) ?? Int.max
            let y = preferredOrder.firstIndex(of: b.id) ?? Int.max
            return x == y ? a.id < b.id : x < y
        }
    }

    /// "Harbour" from "Harbour Dark"; a single theme keeps its LABEL.
    static func label(id: String, values: [String: String], isFamily: Bool) -> String {
        let label = values["LABEL"] ?? id.capitalized
        guard isFamily else { return label }
        for suffix in [" Dark", " Light", " dark", " light"] where label.hasSuffix(suffix) {
            return String(label.dropLast(suffix.count))
        }
        return id.capitalized
    }

    /// The family a theme file belongs to.
    public static func family(of name: String, in families: [ThemeFamily]) -> ThemeFamily? {
        families.first { $0.contains(name) }
    }
}
