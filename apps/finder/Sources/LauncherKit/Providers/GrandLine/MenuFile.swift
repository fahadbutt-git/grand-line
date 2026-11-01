import Foundation

/// The main menu's entries, read like bin/menu reads them: menu.tsv, then
/// menu.local.tsv, where the same path replaces an entry and a command of "-"
/// removes it. Columns: Group/Sub/Label TAB command TAB ?guard TAB ✓check
/// TAB !question. The optional columns may come in any order after the command.
public struct MenuEntry: Sendable, Equatable {
    public let path: String
    public let command: String
    /// A shell test: the entry shows only when it succeeds.
    public let guardTest: String?
    /// A shell test: the entry is ticked when it succeeds.
    public let checkTest: String?
    /// "!Press Return again to restart": the first Return shows this and only
    /// a second Return runs it. A command that restarts, shuts down, logs out
    /// or sleeps asks even without the column (`confirmation`).
    public let question: String?

    public init(path: String, command: String, guardTest: String? = nil, checkTest: String? = nil, question: String? = nil) {
        self.path = path
        self.command = command
        self.guardTest = guardTest
        self.checkTest = checkTest
        self.question = question
    }

    /// The question asked before the entry runs, if it asks: its own "!"
    /// column, or a plain one for an irreversible command without it.
    public var confirmation: String? {
        if let question { return question.isEmpty ? "Press Return again to run \(label)" : question }
        return UsagePolicy.isIrreversible(.shell(command)) ? "Press Return again to run \(label)" : nil
    }

    public var label: String { path.split(separator: "/").last.map(String.init) ?? path }
    public var groups: [String] { path.split(separator: "/").dropLast().map(String.init) }
}

public enum MenuFile {
    public static func parse(_ texts: [String]) -> [MenuEntry] {
        var order: [String] = []
        var byPath: [String: MenuEntry] = [:]
        for text in texts {
            for row in TSV.rows(text) where row.count >= 2 && !row[0].isEmpty {
                var guardTest: String?
                var checkTest: String?
                var question: String?
                for field in row.dropFirst(2) {
                    if field.hasPrefix("?") { guardTest = String(field.dropFirst()) }
                    else if field.hasPrefix("✓") { checkTest = String(field.dropFirst()) }
                    else if field.hasPrefix("!") { question = String(field.dropFirst()).trimmingCharacters(in: .whitespaces) }
                }
                if byPath[row[0]] == nil { order.append(row[0]) }
                byPath[row[0]] = MenuEntry(path: row[0], command: row[1], guardTest: guardTest, checkTest: checkTest, question: question)
            }
        }
        return order.compactMap { byPath[$0] }.filter { $0.command != "-" }
    }

    public static func load(_ paths: GrandLinePaths) -> [MenuEntry] {
        let texts = [paths.menu, paths.menuLocal].compactMap { try? String(contentsOfFile: $0, encoding: .utf8) }
        return parse(texts)
    }
}

/// Runs every guard and check in one bash process, as bin/menu does, and reads
/// back two digits per entry: shown, then ticked.
public enum MenuStateProbe {
    public struct State: Sendable, Equatable {
        public let shown: Bool
        public let checked: Bool
    }

    public static func script(for entries: [MenuEntry], helpers: String) -> String {
        var script = "source \(ShellQuote.quote(helpers)) 2>/dev/null"
        for entry in entries {
            let g = entry.guardTest ?? "true"
            let c = entry.checkTest ?? "false"
            script += "\nif { \(g); } >/dev/null 2>&1; then s=1; else s=0; fi"
            script += "\nif [ $s = 1 ] && { \(c); } >/dev/null 2>&1; then echo ${s}1; else echo ${s}0; fi"
        }
        return script
    }

    /// One state per entry. Missing lines (the probe failed) count as shown and unticked,
    /// except for entries with a guard, which stay hidden.
    public static func parse(_ output: String, entries: [MenuEntry]) -> [State] {
        let lines = output.split(separator: "\n").map(String.init)
        return entries.indices.map { i in
            guard i < lines.count, lines[i].count == 2 else {
                return State(shown: entries[i].guardTest == nil, checked: false)
            }
            return State(shown: lines[i].first == "1", checked: lines[i].last == "1")
        }
    }

    public static func needsProbe(_ entries: [MenuEntry]) -> Bool {
        entries.contains { $0.guardTest != nil || $0.checkTest != nil }
    }
}
