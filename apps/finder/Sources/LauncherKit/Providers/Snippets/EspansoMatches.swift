import Foundation

/// One Espanso text shortcut: its triggers and the text it becomes.
public struct Snippet: Sendable, Equatable {
    public let triggers: [String]
    public let replace: String
    public let label: String?
    /// The file it came from, without the folder.
    public let file: String
    /// Whether some {{variable}} could not be filled in here (a shell or form
    /// variable), so the trigger is typed for Espanso to expand instead.
    public let isDynamic: Bool
}

/// Reads Espanso's match files: the trigger, triggers, replace and label of each
/// match, with date variables (and global ones) filled in.
public enum EspansoMatches {
    public static func parse(_ text: String, file: String, now: Date = Date(), calendar: Calendar = .current) -> [Snippet] {
        guard let root = MiniYAML.parse(text) else { return [] }
        let globals = variables(root["global_vars"], now: now, calendar: calendar)
        return (root["matches"]?.array ?? []).compactMap { match in
            var triggers: [String] = []
            if let one = match["trigger"]?.string { triggers.append(one) }
            triggers += (match["triggers"]?.array ?? []).compactMap(\.string)
            guard !triggers.isEmpty, let replace = match["replace"]?.string else { return nil }
            let values = globals.merging(variables(match["vars"], now: now, calendar: calendar)) { _, own in own }
            let filled = fill(replace, values)
            return Snippet(
                triggers: triggers,
                replace: filled,
                label: match["label"]?.string,
                file: file,
                isDynamic: filled.contains("{{")
            )
        }
    }

    /// Date variables rendered now; other kinds are left out.
    static func variables(_ value: YAMLValue?, now: Date, calendar: Calendar) -> [String: String] {
        var values: [String: String] = [:]
        for item in value?.array ?? [] {
            guard let name = item["name"]?.string, item["type"]?.string == "date",
                  let format = item["params"]?["format"]?.string else { continue }
            values[name] = DateText.strftime(format, now, calendar: calendar)
        }
        return values
    }

    static func fill(_ text: String, _ values: [String: String]) -> String {
        var out = text
        for (name, value) in values {
            out = out.replacingOccurrences(of: "{{\(name)}}", with: value)
                .replacingOccurrences(of: "{{ \(name) }}", with: value)
        }
        return out
    }

    /// Every .yml and .yaml file in the match folder and its subfolders, except
    /// those starting with _ (Espanso's own rule).
    public static func load(folder: String, fileManager: FileManager = .default, now: Date = Date()) -> [Snippet] {
        guard let walker = fileManager.enumerator(atPath: folder) else { return [] }
        var snippets: [Snippet] = []
        for case let relative as String in walker {
            let name = (relative as NSString).lastPathComponent
            guard name.hasSuffix(".yml") || name.hasSuffix(".yaml"), !name.hasPrefix("_") else { continue }
            guard let text = try? String(contentsOfFile: folder + "/" + relative, encoding: .utf8) else { continue }
            snippets += parse(text, file: name, now: now)
        }
        return snippets
    }

    public static func results(_ snippets: [Snippet]) -> [LaunchResult] {
        snippets.map { snippet in
            let trigger = snippet.triggers[0]
            let preview = snippet.replace.replacingOccurrences(of: "\n", with: " ⏎ ")
            let insert: LaunchAction = snippet.isDynamic
                ? LaunchAction("Type the trigger", symbol: "keyboard", .typeText(trigger))
                : LaunchAction("Paste", symbol: "doc.on.clipboard", .paste(snippet.replace))
            return LaunchResult(
                id: "snip:" + trigger,
                title: snippet.label ?? preview,
                subtitle: snippet.triggers.joined(separator: "  ") + " · " + snippet.file,
                icon: .symbol("text.quote"),
                section: .snippets,
                keywords: snippet.triggers + (snippet.label == nil ? [] : [preview]),
                aliases: snippet.triggers.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ";:")) },
                accessory: trigger,
                actions: [insert, .copy(snippet.replace, title: "Copy text")],
                detail: snippet.replace,
                providerID: "snippets"
            )
        }
    }

    public static func provider(paths: GrandLinePaths = GrandLinePaths()) -> CatalogProvider {
        CatalogProvider(id: "snippets", title: "Snippets", symbol: "text.quote", prefix: .snippets, globalLimit: 10) {
            results(load(folder: paths.espansoMatches))
        }
    }
}
