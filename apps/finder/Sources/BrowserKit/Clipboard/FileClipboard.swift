import Foundation

/// Real cut and paste (R8). Cmd+X marks items to move and dims them; Cmd+V
/// then moves them. Copying, or anything else reaching the pasteboard after the
/// cut (its change count moves on), makes Cmd+V copy instead, as Finder does.
public struct FileClipboard: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        case copy
        case cut
    }

    public struct PastePlan: Equatable, Sendable {
        public let items: [URL]
        public let moves: Bool
    }

    public private(set) var mode: Mode = .copy
    public private(set) var items: [URL] = []
    /// The pasteboard's change count right after the cut wrote to it.
    public private(set) var cutChangeCount: Int?
    /// The pasteboard's change count right after Nexus's own copy wrote to it.
    public private(set) var copyChangeCount: Int?

    public init() {}

    /// `changeCount` is the pasteboard's right after the copy wrote to it:
    /// while it stays the same, a paste takes these items as they were
    /// copied, without reading them back from the pasteboard.
    public mutating func copy(_ urls: [URL], changeCount: Int? = nil) {
        mode = .copy
        items = urls
        cutChangeCount = nil
        copyChangeCount = changeCount
    }

    public mutating func cut(_ urls: [URL], changeCount: Int) {
        mode = .cut
        items = urls
        cutChangeCount = changeCount
        copyChangeCount = nil
    }

    public mutating func clear() {
        self = FileClipboard()
    }

    /// Rows waiting to be moved are drawn dimmed.
    public func isCut(_ url: URL) -> Bool {
        mode == .cut && items.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    public var cutPaths: Set<String> {
        mode == .cut ? Set(items.map { $0.standardizedFileURL.path }) : []
    }

    /// What Cmd+V does with what is on the pasteboard now. `forceMove` is
    /// Option+Cmd+V (Move Item Here).
    public func plan(pasteboard urls: [URL], changeCount: Int, forceMove: Bool = false) -> PastePlan? {
        plan(reading: { urls }, changeCount: changeCount, forceMove: forceMove)
    }

    /// The same, reading the pasteboard only when the items are not Nexus's
    /// own cut or copy, still on it. What is read is cleaned (`pastedURLs`).
    public func plan(reading pasteboard: () -> [URL], changeCount: Int, forceMove: Bool = false) -> PastePlan? {
        if mode == .cut, let cutChangeCount, cutChangeCount == changeCount, !items.isEmpty {
            return PastePlan(items: items, moves: true)
        }
        if mode == .copy, let copyChangeCount, copyChangeCount == changeCount, !items.isEmpty {
            return PastePlan(items: items, moves: forceMove)
        }
        let urls = Self.pastedURLs(pasteboard())
        guard !urls.isEmpty else { return nil }
        return PastePlan(items: urls, moves: forceMove)
    }

    /// File URLs from the pasteboard as paths. macOS hands file URLs back as
    /// file reference URLs ("file:///.file/id=6571367.2773272"), whose last
    /// component is "id=6571367.2773272", not the item's name: pasted as they
    /// are, the copy was named that, and the item already there under its own
    /// name was never seen as a conflict. Each becomes its path URL, once.
    public static func pastedURLs(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        var result: [URL] = []
        for url in urls where url.isFileURL {
            let path = ((url as NSURL).filePathURL ?? url).standardizedFileURL
            guard !path.path.hasPrefix("/.file/"), seen.insert(path.path).inserted else { continue }
            result.append(path)
        }
        return result
    }

    /// After a paste: a cut is used up, a copy can be pasted again.
    public mutating func didPaste(_ plan: PastePlan) {
        if plan.moves { clear() }
    }
}
