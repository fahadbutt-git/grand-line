import Foundation

/// The rows offered when nothing matches, under Other actions below the web
/// engines from Settings, Web (which FallbackProvider adds to every search):
/// calculate it, create a file of that name in Downloads, and run it in
/// Terminal. Running is never automatic: its Return asks first and a second
/// Return runs it.
public struct FallbackCommandsProvider: InstantProvider, NoMatchProvider {
    public static let providerID = "fallback-commands"
    public let id = FallbackCommandsProvider.providerID
    public let title = "When nothing matches"
    public let symbol = "questionmark.circle"
    public let prefix: Prefix? = nil
    public let inGlobalSearch = true
    let paths: GrandLinePaths

    public init(paths: GrandLinePaths = GrandLinePaths()) {
        self.paths = paths
    }

    /// Only when the other providers found nothing; see NoMatchProvider.
    public func instantResults(for query: LaunchQuery) -> [LaunchResult] { [] }

    /// A safe file name from what was typed: slashes and colons become dashes,
    /// no leading dots. nil when nothing is left.
    public static func fileName(_ text: String) -> String? {
        var name = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        name = String(name.drop(while: { $0 == "." })).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, name.utf8.count <= 255, !name.contains(where: \.isNewline) else { return nil }
        return name
    }

    public func noMatchResults(for query: LaunchQuery) -> [LaunchResult] {
        let term = query.term
        guard !term.isEmpty else { return [] }
        var rows: [LaunchResult] = []
        if term.contains(where: \.isNumber) {
            rows.append(LaunchResult(
                id: "fallback:calculate",
                title: "Calculate “\(term)”",
                subtitle: "With the calculator, units and dates",
                icon: .symbol("equal.square"),
                section: .otherActions,
                accessory: "=",
                actions: [LaunchAction.complete("=" + term, title: "Calculate")],
                isFallback: true,
                providerID: id,
                match: MatchInfo(quality: -1)
            ))
        }
        if let name = Self.fileName(term) {
            let path = paths.downloads + "/" + name
            rows.append(LaunchResult(
                id: "fallback:create-file",
                title: "Create file “\(name)” in Downloads",
                subtitle: paths.abbreviate(path),
                icon: .symbol("doc.badge.plus"),
                section: .otherActions,
                accessory: "New file",
                actions: [
                    LaunchAction("Create file", symbol: "doc.badge.plus", .createFile(path)),
                    LaunchAction.copy(name, title: "Copy name"),
                ],
                isFallback: true,
                providerID: id,
                match: MatchInfo(quality: -2)
            ))
        }
        rows.append(LaunchResult(
            id: "fallback:run-terminal",
            title: "Run “\(term)” in Terminal",
            subtitle: "In a terminal window (zsh). Return asks first",
            icon: .symbol("terminal"),
            section: .otherActions,
            accessory: "Shell",
            actions: [
                LaunchAction("Run in Terminal", symbol: "terminal", confirmation: "Run “\(term)” in Terminal?",
                             .run(paths.command("in-window"), arguments: ["/bin/zsh", "-lc", term])),
                LaunchAction.copy(term, title: "Copy command"),
            ],
            isFallback: true,
            providerID: id,
            match: MatchInfo(quality: -3)
        ))
        return rows
    }
}
