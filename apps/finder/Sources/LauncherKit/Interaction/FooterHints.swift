import Foundation

/// The shortcuts shown at the bottom of the window for the selected row,
/// read as "Open ↵ · Show in Nexus ⌘↵ · Actions ⌘K": what Return does first,
/// in the row's own words. While Command or Option is held, the first hint
/// is what Return does with that modifier.
public enum FooterHints {
    public struct Hint: Sendable, Equatable, Hashable {
        public let keys: String
        public let label: String
    }

    public static let returnKey = "\u{21B5}"

    public static func hints(for result: LaunchResult?, confirming: ConfirmationGate.Pending?, held: HeldModifier = .none) -> [Hint] {
        if let confirming {
            return [Hint(keys: returnKey, label: confirming.question), Hint(keys: "\u{238B}", label: "cancel")]
        }
        guard let result else { return [Hint(keys: "/", label: "Prefixes")] }
        var hints: [Hint] = []
        switch held {
        case .command:
            if let secondary = result.secondary { hints.append(Hint(keys: "\u{2318}" + returnKey, label: secondary.title)) }
        case .option:
            if let alternate = ActionPanel.alternate(for: result) { hints.append(Hint(keys: "\u{2325}" + returnKey, label: alternate.title)) }
        case .none:
            if let primary = result.primary { hints.append(Hint(keys: returnKey, label: primary.title)) }
            if let secondary = result.secondary { hints.append(Hint(keys: "\u{2318}" + returnKey, label: secondary.title)) }
        }
        if !ActionPanel.actions(for: result).isEmpty { hints.append(Hint(keys: "\u{2318}K", label: "Actions")) }
        // Quick Look is in the action panel for files; a definition has only this key.
        if result.previewPath == nil, result.detail != nil { hints.append(Hint(keys: "\u{2318}Y", label: "Preview")) }
        return hints
    }
}
