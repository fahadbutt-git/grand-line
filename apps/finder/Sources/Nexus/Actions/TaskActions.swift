import AppKit
import BrowserKit
import FileKit

/// Copy and move as tasks: taken names are asked about once, before the task
/// starts (the conflict sheet), then the work runs in the task engine.
extension BrowserModel {
    /// Copies or moves `items` into `folder`, then selects the result in
    /// `target` when it shows that folder.
    func transfer(_ items: [URL], to folder: URL, moving: Bool, select target: PaneModel?) {
        guard !items.isEmpty else { return }
        let services = self.services
        let window = self.window
        Task {
            do {
                let outcome = try await TransferFlow.run(items, to: folder, moving: moving, queue: services.tasks) { conflict, remaining in
                    await ConflictPrompt.ask(conflict, remaining: remaining, moving: moving, in: window)
                }
                guard case .done(let made) = outcome else { return }
                if let target, target.location.folderURL?.standardizedFileURL == folder.standardizedFileURL {
                    target.go(.folder(folder), select: made)
                }
            } catch is CancellationError {
                target?.reload()
            } catch {
                Prompt.problem(moving ? "The items could not be moved." : "The items could not be copied.", error)
            }
            services.refreshUndo()
        }
    }

    /// The tasks popover's Undo on an older entry: everything newer is undone too.
    func undoHistory(through index: Int) {
        undo(steps: index + 1)
    }
}

/// A tool's error text as an error, for a task that ran one (Compress).
struct TaskProblem: LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var errorDescription: String? { message.isEmpty ? nil : message }
}

/// The conflict sheet: Keep Both (Return), Replace, Skip or Stop (Escape),
/// with Apply to All when more items have the same problem. Replace moves the
/// old item to the Trash, so Undo brings it back.
@MainActor
enum ConflictPrompt {
    static func ask(_ conflict: FileConflict, remaining: Int, moving: Bool, in window: NSWindow?) async -> ConflictAnswer? {
        let alert = NSAlert()
        alert.messageText = ConflictQuestions.message(for: conflict)
        alert.informativeText = ConflictQuestions.detail(for: conflict, remaining: remaining)
        alert.addButton(withTitle: "Keep Both")
        alert.addButton(withTitle: "Replace")
        alert.addButton(withTitle: moving ? "Don\u{2019}t Move" : "Skip")
        let stop = alert.addButton(withTitle: "Stop")
        stop.keyEquivalent = "\u{1b}"
        if remaining > 0 {
            alert.showsSuppressionButton = true
            alert.suppressionButton?.title = "Apply to all"
        }
        alert.window.setAccessibilityIdentifier("nexus.conflict")
        let response: NSApplication.ModalResponse
        if let window, window.isVisible, window.attachedSheet == nil {
            response = await alert.beginSheetModal(for: window)
        } else {
            response = alert.runModal()
        }
        let all = alert.suppressionButton?.state == .on
        switch response {
        case .alertFirstButtonReturn: return ConflictAnswer(.keepBoth, applyToAll: all)
        case .alertSecondButtonReturn: return ConflictAnswer(.replace, applyToAll: all)
        case .alertThirdButtonReturn: return ConflictAnswer(.skip, applyToAll: all)
        default: return nil
        }
    }
}
