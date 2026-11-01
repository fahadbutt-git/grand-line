import Foundation

/// What an `iceberg://` URL asks for: `toggle`, `open`, `close`, `reload`,
/// `settings`, and `trigger/NAME` (or `trigger?widget=NAME`), which runs a
/// widget. `denden` is the former scheme, kept so older shortcuts work.
public enum URLCommand: Equatable, Sendable {
    case toggle, open, close, reload, settings
    case trigger([String])

    public static let schemes: Set<String> = ["iceberg", "denden"]

    public static func parse(_ url: URL) -> URLCommand? {
        guard schemes.contains(url.scheme?.lowercased() ?? "") else { return nil }
        switch (url.host ?? url.path).lowercased() {
        case "toggle": return .toggle
        case "open": return .open
        case "close": return .close
        case "reload": return .reload
        case "settings": return .settings
        case "trigger":
            let fromPath = url.pathComponents.filter { $0 != "/" }
            let fromQuery = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.filter { $0.name == "widget" }.compactMap(\.value) ?? []
            let names = (fromPath + fromQuery).filter { !$0.isEmpty }
            return names.isEmpty ? nil : .trigger(names)
        default: return nil
        }
    }
}

/// URLs that arrive before the app is ready. On a cold launch from a URL
/// (`open -g iceberg://trigger/NAME`), AppKit can deliver it before
/// applicationDidFinishLaunching has built the panels and widgets; those
/// commands wait here and run, in order, once setup is done.
public struct LaunchQueue: Sendable {
    public private(set) var isReady = false
    private var waiting: [URLCommand] = []
    /// A burst of URLs before launch finishes is kept to a sane size.
    public static let limit = 32

    public init() {}

    /// Returns the command to run now, or nil when it was queued (or is not
    /// an Iceberg command).
    public mutating func receive(_ url: URL) -> URLCommand? {
        guard let command = URLCommand.parse(url) else { return nil }
        if isReady { return command }
        if waiting.count < Self.limit { waiting.append(command) }
        return nil
    }

    /// Setup is done: returns what waited, in order, and runs later ones at once.
    public mutating func becomeReady() -> [URLCommand] {
        isReady = true
        defer { waiting = [] }
        return waiting
    }
}
