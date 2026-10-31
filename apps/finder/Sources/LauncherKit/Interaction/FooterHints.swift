import Foundation

/// The shortcuts shown at the bottom of the window for the selected row.
public enum FooterHints {
    public struct Hint: Sendable, Equatable, Hashable {
        public let keys: String
        public let label: String
    }

    public static func hints(for result: LaunchResult?, confirming: ConfirmationGate.Pending?) -> [Hint] {
        if let confirming {
            return [Hint(keys: "↩", label: confirming.question), Hint(keys: "⎋", label: "cancel")]
        }
        guard let result else { return [Hint(keys: "/", label: "prefixes")] }
        var hints: [Hint] = []
        if let primary = result.primary { hints.append(Hint(keys: "↩", label: primary.title.lowercased())) }
        if let secondary = result.secondary { hints.append(Hint(keys: "⌘↩", label: secondary.title.lowercased())) }
        if ActionPanel.actions(for: result).count > 2 { hints.append(Hint(keys: "⌘K", label: "actions")) }
        if FileBuffer.path(of: result) != nil { hints.append(Hint(keys: "⌘B", label: "buffer")) }
        if result.previewPath != nil || result.detail != nil { hints.append(Hint(keys: "⌘Y", label: "preview")) }
        return hints
    }
}
