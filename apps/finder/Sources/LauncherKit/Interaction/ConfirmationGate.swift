import Foundation

/// Actions with a confirmation (quit a process) run on the second Return. Any
/// other key, a new query or a different row cancels the first.
public struct ConfirmationGate: Sendable, Equatable {
    public private(set) var pending: Pending?

    public struct Pending: Sendable, Equatable {
        public let resultID: String
        public let action: LaunchAction
        public var question: String { action.confirmation ?? "" }
    }

    public init() {}

    /// Whether to run `action` now. Returns false the first time an action that
    /// needs confirming is asked for, and true when the same one is asked again.
    public mutating func shouldRun(_ action: LaunchAction, on resultID: String) -> Bool {
        guard action.confirmation != nil else {
            pending = nil
            return true
        }
        if let pending, pending.resultID == resultID, pending.action == action {
            self.pending = nil
            return true
        }
        pending = Pending(resultID: resultID, action: action)
        return false
    }

    public mutating func cancel() {
        pending = nil
    }

    public var isConfirming: Bool { pending != nil }
}
