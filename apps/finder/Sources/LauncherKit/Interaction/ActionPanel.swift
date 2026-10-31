import Foundation

/// What kind of thing a row is, for the actions every row of its kind offers.
public enum ResultKind: Sendable, Equatable {
    case file(path: String, isFolder: Bool)
    case app(path: String)
    case calculator
    case bookmark(url: String)
    case command
    case link(url: String)
    case other

    public static func of(_ result: LaunchResult) -> ResultKind {
        if result.id.hasPrefix("file:") {
            // File rows offer Open with… for files and not for folders.
            let isFolder = !result.actions.contains { if case .openWith = $0.command { return true } else { return false } }
            return .file(path: String(result.id.dropFirst(5)), isFolder: isFolder)
        }
        if result.id.hasPrefix("app:") { return .app(path: String(result.id.dropFirst(4))) }
        if result.providerID == "calculator" { return .calculator }
        if result.id.hasPrefix("bm:") { return .bookmark(url: String(result.id.dropFirst(3))) }
        if ["commands", "menu", ScriptCommandsProvider.providerID].contains(result.providerID) || result.id.hasPrefix("cmd:") {
            return .command
        }
        for action in result.actions {
            if case .openURL(let url, _) = action.command { return .link(url: url) }
        }
        return .other
    }
}

/// Command+K: every row's own actions, then the ones every row of its kind
/// has (open with, show in Nexus, copy path and name, Quick Look, move to the
/// Trash, add to the buffer for files; copy the result of a sum; open and copy
/// a link). With files in the buffer, or on the Finder or Nexus selection,
/// the actions apply to all of them.
public enum ActionPanel {
    public static func actions(for result: LaunchResult) -> [LaunchAction] {
        var list = result.actions
        func add(_ action: LaunchAction) {
            guard !list.contains(where: { $0.command == action.command }) else { return }
            list.append(action)
        }
        func hasCopy() -> Bool {
            list.contains { if case .copyText = $0.command { return true } else { return false } }
        }
        switch ResultKind.of(result) {
        case .file(let path, let isFolder):
            let name = (path as NSString).lastPathComponent
            add(LaunchAction(isFolder ? "Open in Nexus" : "Open", symbol: "arrow.up.forward", .open(path)))
            if !isFolder { add(LaunchAction("Open with…", symbol: "arrow.up.right.square", shortcut: KeyShortcut("o"), .openWith(path))) }
            add(LaunchAction("Show in Nexus", symbol: "folder", .reveal(path)))
            add(LaunchAction("Quick Look", symbol: "eye", shortcut: KeyShortcut("y"), closesWindow: false, .quickLook(path)))
            add(LaunchAction("Copy path", symbol: "doc.on.clipboard", shortcut: KeyShortcut("c", option: true), .copyText(path)))
            add(LaunchAction("Copy name", symbol: "textformat", shortcut: KeyShortcut("n", shift: true), .copyText(name)))
            add(LaunchAction("Copy file", symbol: "doc.on.doc", shortcut: KeyShortcut("c", shift: true), .copyFile(path)))
            add(LaunchAction("Add to buffer", symbol: "tray.and.arrow.down", shortcut: KeyShortcut("b"), closesWindow: false, .buffer([path])))
            add(trash([path]))
        case .app(let path):
            let name = (path as NSString).lastPathComponent
            add(LaunchAction("Show in Nexus", symbol: "folder", .reveal(path)))
            add(LaunchAction("Copy path", symbol: "doc.on.clipboard", .copyText(path)))
            add(LaunchAction("Copy name", symbol: "textformat", shortcut: KeyShortcut("n", shift: true),
                             .copyText(name.hasSuffix(".app") ? String(name.dropLast(4)) : name)))
        case .calculator:
            if !hasCopy(), !result.title.isEmpty { add(LaunchAction("Copy result", symbol: "doc.on.doc", .copyText(result.title))) }
        case .bookmark(let url):
            add(LaunchAction("Open", symbol: "globe", .openURL(url, bundleID: nil)))
            add(LaunchAction.copy(url, title: "Copy URL"))
            add(LaunchAction("Copy title", symbol: "textformat", .copyText(result.title)))
        case .link(let url):
            add(LaunchAction.copy(url, title: "Copy URL"))
        case .command:
            if !hasCopy() { add(LaunchAction("Copy name", symbol: "textformat", .copyText(result.title))) }
        case .other:
            if !hasCopy(), !result.title.isEmpty { add(LaunchAction("Copy title", symbol: "textformat", .copyText(result.title))) }
        }
        return list
    }

    /// Moves files to the Trash after a second Return. Nothing is ever deleted.
    public static func trash(_ paths: [String]) -> LaunchAction {
        let what = paths.count == 1 ? "“\((paths[0] as NSString).lastPathComponent)”" : "\(paths.count) items"
        return LaunchAction("Move to Trash", symbol: "trash", confirmation: "Move \(what) to the Trash?", .files(.trash, paths))
    }

    /// The actions for several files: the buffer or a selection.
    public static func fileActions(_ paths: [String], inBuffer: Bool) -> [LaunchAction] {
        guard !paths.isEmpty else { return [] }
        let names = paths.map { ($0 as NSString).lastPathComponent }
        let count = paths.count == 1 ? names[0] : "\(paths.count) items"
        var list: [LaunchAction] = [
            LaunchAction("Open \(count)", symbol: "arrow.up.forward", .files(.open, paths)),
            LaunchAction("Show in Nexus", symbol: "folder", .files(.reveal, paths)),
            LaunchAction("Quick Look", symbol: "eye", closesWindow: false, .files(.quickLook, paths)),
            LaunchAction("Copy paths", symbol: "doc.on.clipboard", .copyText(paths.joined(separator: "\n"))),
            LaunchAction("Copy names", symbol: "textformat", .copyText(names.joined(separator: "\n"))),
            LaunchAction("Copy files", symbol: "doc.on.doc", .files(.copyFiles, paths)),
            LaunchAction("Move to…", symbol: "folder.badge.plus", .files(.moveTo, paths)),
            LaunchAction("AirDrop", symbol: "airplayaudio", .files(.airDrop, paths)),
            trash(paths),
        ]
        if inBuffer {
            list.append(LaunchAction("Clear buffer", symbol: "xmark.circle", closesWindow: false, .clearBuffer))
        } else {
            list.append(LaunchAction("Add to buffer", symbol: "tray.and.arrow.down", closesWindow: false, .buffer(paths)))
        }
        return list
    }
}

/// The open Command+K panel and its keys. Up and Down move, Return runs the
/// action (a second Return when it asks first), an action's own shortcut runs
/// it, Command+K or Escape close the panel (Escape first cancels a question).
public struct ActionPanelModel: Sendable, Equatable {
    public var title: String
    public var actions: [LaunchAction]
    public var selected: Int
    public var result: LaunchResult
    /// The files the actions apply to, when they are the buffer or a selection.
    public var files: [String]

    public init(title: String, actions: [LaunchAction], selected: Int = 0, result: LaunchResult, files: [String] = []) {
        self.title = title
        self.actions = actions
        self.selected = min(max(selected, 0), max(actions.count - 1, 0))
        self.result = result
        self.files = files
    }

    public enum Outcome: Sendable, Equatable {
        /// The panel used the key and stays open.
        case handled
        /// Close the panel and run this action (already confirmed).
        case run(LaunchAction)
        case close
        /// Not a panel key.
        case passThrough
    }

    public mutating func handle(_ command: KeyCommand, gate: inout ConfirmationGate) -> Outcome {
        switch command {
        case .moveUp, .pageUp:
            gate.cancel()
            selected = max(0, selected - (command == .moveUp ? 1 : 8))
            return .handled
        case .moveDown, .pageDown:
            gate.cancel()
            selected = min(max(actions.count - 1, 0), selected + (command == .moveDown ? 1 : 8))
            return .handled
        case .primary:
            guard actions.indices.contains(selected) else { return .handled }
            return attempt(actions[selected], gate: &gate)
        case .shortcut(let shortcut):
            guard let index = actions.firstIndex(where: { $0.shortcut == shortcut }) else { return .passThrough }
            selected = index
            return attempt(actions[index], gate: &gate)
        case .actions:
            gate.cancel()
            return .close
        case .escape:
            if gate.isConfirming {
                gate.cancel()
                return .handled
            }
            return .close
        default:
            return .passThrough
        }
    }

    /// Runs it, or asks first and stays open when it needs confirming.
    private func attempt(_ action: LaunchAction, gate: inout ConfirmationGate) -> Outcome {
        gate.shouldRun(action, on: result.id) ? .run(action) : .handled
    }
}
