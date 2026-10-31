import Foundation

/// Escape backs out one step at a time: the action panel, then a pending
/// confirmation, then the query, and only then the window.
public enum EscapeRule {
    public enum Outcome: Sendable, Equatable {
        case closeActionPanel
        case cancelConfirmation
        case clearQuery
        case closeWindow
    }

    public static func outcome(actionPanelOpen: Bool, confirming: Bool, query: String) -> Outcome {
        if actionPanelOpen { return .closeActionPanel }
        if confirming { return .cancelConfirmation }
        if !query.isEmpty { return .clearQuery }
        return .closeWindow
    }
}
