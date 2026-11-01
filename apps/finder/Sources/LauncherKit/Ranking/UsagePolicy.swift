import Foundation

/// What may be learned from a pick, and which rows always ask first.
///
/// - Rows that end the session or another app's work (restart, shut down, log
///   out, sleep, quit, force quit) always need a second Return, wherever they
///   show: a menu row, a favourite, a top hit. They are never written to
///   recents or to learned abbreviations, and learning never lifts them.
/// - Clipboard history rows carry what was copied (a password, a token). They
///   are never written to usage.json at all.
/// - Rows that name a running process or the front app's menus carry a pid,
///   which means another process tomorrow. They are never replayed later.
/// - The selection and the buffer are not rows to come back to.
public enum UsagePolicy {
    /// Providers whose rows are never recorded or kept as favourites.
    public static let unrecordedProviders: Set<String> = [
        ClipboardHistoryProvider.providerID, ProcessProvider.providerID, MenuBarItems.providerID, SelectionProvider.providerID,
    ]

    /// Row ids of those providers, for entries saved before this rule (their
    /// provider id is in the snapshot too, but ids without one are matched by these).
    static let unrecordedIDPrefixes = ["clip:", "proc:", "menuitem:"]

    /// The bin/power actions that end the session or put the Mac to sleep.
    /// Lock and display sleep lose nothing.
    public static let irreversiblePower: Set<String> = ["sleep", "logout", "restart", "shutdown"]

    /// Commands that cannot be taken back: a bin/power action that ends the
    /// session (as an argument list or a shell line), the system's own
    /// shutdown commands, or quitting a process.
    public static func isIrreversible(_ command: ActionCommand) -> Bool {
        switch command {
        case .quit:
            return true
        case .run(let executable, let arguments):
            switch (executable as NSString).lastPathComponent {
            case "power", "shutdown", "reboot", "halt", "pmset": return isIrreversible(words: [executable] + arguments)
            default: return false
            }
        case .shell(let line):
            return isIrreversible(words: line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init))
        default:
            return false
        }
    }

    /// The row with a question on every action that cannot be taken back and
    /// has none: whichever provider made it (a menu line, a shortcut, an old
    /// favourite, an external provider), Return asks first.
    public static func guarding(_ result: LaunchResult) -> LaunchResult {
        guard result.actions.contains(where: { $0.confirmation == nil && isIrreversible($0.command) }) else { return result }
        var guarded = result
        for i in guarded.actions.indices where guarded.actions[i].confirmation == nil && isIrreversible(guarded.actions[i].command) {
            guarded.actions[i].confirmation = "Press Return again to run \(result.title)"
        }
        return guarded
    }

    static func isIrreversible(words: [String]) -> Bool {
        // Leading VAR=value assignments and `exec` do not change what runs.
        var rest = words.drop { $0.contains("=") && !$0.hasPrefix("=") || $0 == "exec" || $0 == "command" }
        guard let first = rest.first else { return false }
        rest = rest.dropFirst()
        let name = (first.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) as NSString).lastPathComponent
        let argument = rest.first?.trimmingCharacters(in: CharacterSet(charactersIn: "\"'")) ?? ""
        switch name {
        case "power": return irreversiblePower.contains(argument)
        case "shutdown", "reboot", "halt": return true
        case "pmset": return argument == "sleepnow"
        default: return false
        }
    }

    /// Whether any of the row's actions cannot be taken back.
    public static func hasIrreversibleAction(_ result: LaunchResult) -> Bool {
        result.actions.contains { isIrreversible($0.command) }
    }

    /// Whether the row asks before it acts, or should: learning never lifts it.
    public static func asksFirst(_ result: LaunchResult) -> Bool {
        result.actions.contains { $0.confirmation != nil } || hasIrreversibleAction(result)
    }

    /// Every action that cannot be taken back carries a question.
    public static func isGuarded(_ result: LaunchResult) -> Bool {
        result.actions.allSatisfy { !isIrreversible($0.command) || $0.confirmation != nil }
    }

    static func fromUnrecordedProvider(_ result: LaunchResult) -> Bool {
        unrecordedProviders.contains(result.providerID) || unrecordedIDPrefixes.contains { result.id.hasPrefix($0) }
    }

    /// Whether a pick of this row may be written to usage.json (scores,
    /// recents, abbreviations).
    public static func mayRecord(_ result: LaunchResult) -> Bool {
        result.id != "buffer" && !fromUnrecordedProvider(result) && !asksFirst(result)
    }

    /// Whether the row may be kept as a favourite: not a clipboard entry or a
    /// pid, and anything irreversible on it still asks first.
    public static func mayFavourite(_ result: LaunchResult) -> Bool {
        result.id != "buffer" && !fromUnrecordedProvider(result) && isGuarded(result)
    }
}
