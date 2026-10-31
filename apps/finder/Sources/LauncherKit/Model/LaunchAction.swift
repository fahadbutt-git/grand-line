import Foundation

/// One thing a row can do. A row's first action runs on Return, its second on
/// Command+Return, and all of them are listed in the Command+K panel.
public struct LaunchAction: Codable, Hashable, Sendable {
    public var title: String
    public var symbol: String
    public var shortcut: KeyShortcut?
    public var command: ActionCommand
    /// When set, the first Return shows this question and only a second Return runs it.
    public var confirmation: String?
    /// Whether the window hides after the action runs.
    public var closesWindow: Bool

    public init(
        _ title: String,
        symbol: String,
        shortcut: KeyShortcut? = nil,
        confirmation: String? = nil,
        closesWindow: Bool = true,
        _ command: ActionCommand
    ) {
        self.title = title
        self.symbol = symbol
        self.shortcut = shortcut
        self.command = command
        self.confirmation = confirmation
        self.closesWindow = closesWindow
    }

    public static func copy(_ text: String, title: String = "Copy") -> LaunchAction {
        LaunchAction(title, symbol: "doc.on.doc", shortcut: KeyShortcut("c", shift: true), .copyText(text))
    }

    public static let favourite = LaunchAction(
        "Favourite", symbol: "star", shortcut: KeyShortcut("f", shift: true), closesWindow: false, .toggleFavourite
    )

    public static func complete(_ query: String, title: String = "Complete") -> LaunchAction {
        LaunchAction(title, symbol: "arrow.right.to.line", closesWindow: false, .setQuery(query))
    }
}
