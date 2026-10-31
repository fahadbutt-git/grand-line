import AppKit
import BrowserKit
import SwiftUI
import UniformTypeIdentifiers

/// Click, Cmd+click, Shift+click, double-click, drag out and the context menu,
/// shared by the icon, gallery and column views.
struct ItemInteraction: ViewModifier {
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    let item: FileItem

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.open([item], in: pane) }
            .onTapGesture { click() }
            .onDrag { provider() }
            .contextMenu {
                ItemMenu(model: model)
            }
    }

    private func click() {
        model.focus(pane)
        let flags = NSEvent.modifierFlags
        pane.updateSelection { selection, order in
            if flags.contains(.command) {
                selection.toggle(item.id, in: order)
            } else if flags.contains(.shift) {
                selection.extend(to: item.id, in: order)
            } else {
                selection.select(item.id)
            }
        }
    }

    private func provider() -> NSItemProvider {
        if !pane.state.selection.contains(item.id) { pane.select(ids: [item.id]) }
        guard !item.isInArchive else { return NSItemProvider() }
        return NSItemProvider(object: item.url as NSURL)
    }
}

/// The SwiftUI form of the context menu.
struct ItemMenu: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        let commands: [[BrowserCommand]] = [
            [.open, .quickLook, .getInfo],
            [.rename, .duplicate, .makeAlias, .compress],
            [.copy, .cut, .copyPath, .share],
            [.extract, .extractTo, .moveToTrash, .putBack],
            [.openTerminal, .openClaude],
        ]
        Menu("Open With") {
            ForEach(model.openWithChoices(), id: \.self) { app in
                Button(app.name) { model.openWith(app.url) }
            }
            Divider()
            Button("Other…") { model.perform(.openWithOther) }
        }
        ForEach(0..<commands.count, id: \.self) { group in
            ForEach(commands[group].filter { model.isEnabled($0) }, id: \.self) { command in
                Button(model.title(for: command)) { model.perform(command) }
            }
            Divider()
        }
        Menu("Tags") {
            ForEach([BrowserCommand.tagRed, .tagOrange, .tagYellow, .tagGreen, .tagBlue, .tagPurple, .tagGray, .removeTags], id: \.self) { command in
                Button(model.title(for: command)) { model.perform(command) }
            }
        }
        let modes = TranscodeMode.allCases.filter { $0.accepts(model.focused.selectedItems) }
        if !modes.isEmpty {
            Menu("Transcode") {
                ForEach(modes, id: \.self) { mode in
                    Button(model.title(for: mode.command)) { model.perform(mode.command) }
                }
            }
        }
    }
}

/// Keys for the SwiftUI views; the list view has its own in the table.
struct BrowserKeys: ViewModifier {
    @ObservedObject var model: BrowserModel
    @ObservedObject var pane: PaneModel
    /// Rows to move for Up and Down: the grid's column count.
    let rowStep: Int

    func body(content: Content) -> some View {
        content
            .focusable()
            .focusEffectDisabled()
            .onKeyPress(phases: .down) { press in
                handle(press) ? .handled : .ignored
            }
    }

    private func handle(_ press: KeyPress) -> Bool {
        let shift = press.modifiers.contains(.shift)
        let key = press.key.character
        let plainArrow = !press.modifiers.contains(.command)
        if key == KeyEquivalent.leftArrow.character { move(-1, shift); return true }
        if key == KeyEquivalent.rightArrow.character { move(1, shift); return true }
        if plainArrow, key == KeyEquivalent.upArrow.character { move(-rowStep, shift); return true }
        if plainArrow, key == KeyEquivalent.downArrow.character { move(rowStep, shift); return true }
        guard let shortcut = Self.shortcut(press) else { return false }
        let context = model.context
        guard let found = KeyMap.command(for: shortcut, inArchive: context.inArchive, inTrash: context.inTrash),
              shortcut.isPlain || [.enclosingFolder, .openSelection, .moveToTrash, .putBack].contains(found) else { return false }
        let command = NexusPreferencesStore.shared.current.returnKey.command(found, for: shortcut)
        if model.isEnabled(command) { model.perform(command) }
        return true
    }

    private func move(_ step: Int, _ extending: Bool) {
        pane.updateSelection { selection, order in selection.move(by: step, in: order, extending: extending) }
    }

    static func shortcut(_ press: KeyPress) -> Shortcut? {
        var modifiers: Shortcut.Modifiers = []
        if press.modifiers.contains(.command) { modifiers.insert(.command) }
        if press.modifiers.contains(.shift) { modifiers.insert(.shift) }
        if press.modifiers.contains(.option) { modifiers.insert(.option) }
        if press.modifiers.contains(.control) { modifiers.insert(.control) }
        let keys: [(KeyEquivalent, Shortcut.Key)] = [
            (.return, .returnKey), (.space, .space), (.tab, .tab), (.delete, .delete), (.upArrow, .up), (.downArrow, .down),
        ]
        for (equivalent, key) in keys where equivalent.character == press.key.character {
            return Shortcut(key, modifiers)
        }
        return nil
    }
}
