import Foundation

/// The key hints along the bottom of the window, for where you are.
public struct FooterHint: Hashable, Sendable {
    public let keys: String
    public let label: String

    public init(_ keys: String, _ label: String) {
        self.keys = keys
        self.label = label
    }
}

public enum FooterHints {
    public static func hints(inArchive: Bool, inTrash: Bool, paneCount: Int, searching: Bool) -> [FooterHint] {
        if inArchive {
            return [
                FooterHint("Space", "preview inside"),
                FooterHint(label(.extract), "extract"),
                FooterHint(label(.extractTo), "extract to"),
                FooterHint(label(.enclosingFolder), "up"),
            ] + paneHints(paneCount)
        }
        if inTrash {
            return [
                FooterHint(label(.putBack), "put back"),
                FooterHint("Space", "preview"),
                FooterHint(label(.emptyTrash), "empty"),
            ]
        }
        var hints = [
            FooterHint("↩", "open"),
            FooterHint("F2", "rename"),
            FooterHint("Space", "preview"),
            FooterHint(label(.enclosingFolder), "up"),
            FooterHint(label(.goToFolder), "path"),
        ]
        if searching {
            hints.append(FooterHint("Esc", "end search"))
        } else {
            hints.append(FooterHint(label(.find), "search"))
        }
        return hints + paneHints(paneCount)
    }

    static func paneHints(_ count: Int) -> [FooterHint] {
        guard count > 1 else { return [] }
        return [FooterHint("Tab", "next pane"), FooterHint("F5", "copy"), FooterHint("F6", "move")]
    }

    static func label(_ command: BrowserCommand) -> String {
        CommandCatalog.spec(command).shortcuts.first?.description ?? ""
    }
}
