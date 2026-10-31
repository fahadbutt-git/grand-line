import Foundation

/// A running app or process that "quit" and "kill" can end.
public struct ProcessEntry: Sendable, Equatable {
    public let pid: Int32
    public let name: String
    public let bundlePath: String?

    public init(pid: Int32, name: String, bundlePath: String? = nil) {
        self.pid = pid
        self.name = name
        self.bundlePath = bundlePath
    }
}

/// "quit safari", "kill zoom", "force quit preview": always asks before it acts.
public final class ProcessProvider: InstantProvider, @unchecked Sendable {
    public let id = "processes"
    public let title = "Quit a process"
    public let symbol = "xmark.octagon"
    public let prefix: Prefix? = nil
    public let inGlobalSearch = true
    private let lock = NSLock()
    private var processes: [ProcessEntry] = []

    public init() {}

    /// The app replaces this list each time the window opens.
    public func set(_ list: [ProcessEntry]) {
        lock.withLock { processes = list }
    }

    /// The name after the command word, and whether it is a force quit.
    public static func parse(_ term: String) -> (name: String, force: Bool)? {
        let lower = term.lowercased()
        for (lead, force) in [("force quit ", true), ("force kill ", true), ("kill ", false), ("quit ", false)] where lower.hasPrefix(lead) {
            return (String(term.dropFirst(lead.count)).trimmingCharacters(in: .whitespaces), force)
        }
        return nil
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        guard query.prefix == nil, let request = Self.parse(query.term), !request.name.isEmpty else { return [] }
        let list = lock.withLock { processes }
        let verb = request.force ? "Force quit" : "Quit"
        // Match on the name alone, then put the verb in front.
        let rows = list.map { entry in
            LaunchResult(
                id: "proc:\(entry.pid)",
                title: entry.name,
                subtitle: "Process \(entry.pid)",
                icon: entry.bundlePath.map { ResultIcon.app($0) } ?? ResultIcon.symbol("gearshape"),
                section: .system,
                actions: [
                    LaunchAction(verb, symbol: "xmark.octagon", confirmation: "\(verb) \(entry.name)? Press Return again", .quit(pid: entry.pid, force: request.force)),
                    LaunchAction("Force quit", symbol: "bolt.octagon", confirmation: "Force quit \(entry.name)? Press Return again", .quit(pid: entry.pid, force: true)),
                ],
                providerID: id
            )
        }
        let shift = verb.utf16.count + 1
        return Catalog(rows).search(request.name, limit: 12).map { row in
            var shown = row
            shown.title = verb + " " + row.title
            shown.match.highlights = row.match.highlights.map { ($0.lowerBound + shift)..<($0.upperBound + shift) }
            return shown
        }
    }
}
