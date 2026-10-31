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

    public init() {}

    public mutating func copy(_ urls: [URL]) {
        mode = .copy
        items = urls
        cutChangeCount = nil
    }

    public mutating func cut(_ urls: [URL], changeCount: Int) {
        mode = .cut
        items = urls
        cutChangeCount = changeCount
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
        if mode == .cut, let cutChangeCount, cutChangeCount == changeCount, !items.isEmpty {
            return PastePlan(items: items, moves: true)
        }
        guard !urls.isEmpty else { return nil }
        return PastePlan(items: urls, moves: forceMove)
    }

    /// After a paste: a cut is used up, a copy can be pasted again.
    public mutating func didPaste(_ plan: PastePlan) {
        if plan.moves { clear() }
    }
}
