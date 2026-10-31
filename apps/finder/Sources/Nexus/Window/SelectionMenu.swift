import AppKit
import BrowserKit

/// The right-click menu for a selection: Finder's items, Open With from
/// default-apps.tsv (R34), Share, Tags, Transcode and the terminal tools (R33).
/// Quick Actions and Services are added by AppKit for the file list.
@MainActor
enum SelectionMenu {
    static func make(for model: BrowserModel) -> NSMenu {
        let menu = NSMenu()
        let selection = model.focused.selectedItems
        if selection.isEmpty {
            add([.newFolder, .paste, .find], to: menu, model)
            menu.addItem(.separator())
            add([.openTerminal, .openClaude, .toggleHidden], to: menu, model)
            return menu
        }
        add([.open], to: menu, model)
        menu.addItem(openWith(model))
        menu.addItem(.separator())
        add([.moveToTrash, .putBack, .extract, .extractTo], to: menu, model)
        menu.addItem(.separator())
        add([.getInfo, .rename, .compress, .duplicate, .makeAlias, .quickLook], to: menu, model)
        menu.addItem(.separator())
        add([.copy, .cut, .copyPath], to: menu, model)
        let urls = model.selectedOnDisk
        if !urls.isEmpty {
            menu.addItem(NSSharingServicePicker(items: urls).standardShareMenuItem)
        }
        menu.addItem(.separator())
        menu.addItem(submenu("Tags", [.tagRed, .tagOrange, .tagYellow, .tagGreen, .tagBlue, .tagPurple, .tagGray, .removeTags], model))
        let modes = TranscodeMode.allCases.filter { $0.accepts(selection) }.map(\.command)
        if !modes.isEmpty { menu.addItem(submenu("Transcode", modes, model)) }
        menu.addItem(.separator())
        add([.openTerminal, .openClaude], to: menu, model)
        return menu
    }

    static func add(_ commands: [BrowserCommand], to menu: NSMenu, _ model: BrowserModel) {
        for command in commands where model.isEnabled(command) {
            let item = MainMenu.item(CommandCatalog.spec(command))
            item.title = model.title(for: command)
            menu.addItem(item)
        }
    }

    static func submenu(_ title: String, _ commands: [BrowserCommand], _ model: BrowserModel) -> NSMenuItem {
        let sub = NSMenu(title: title)
        add(commands, to: sub, model)
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = sub
        return holder
    }

    static func openWith(_ model: BrowserModel) -> NSMenuItem {
        let sub = NSMenu(title: "Open With")
        let choices = model.openWithChoices()
        for (i, app) in choices.enumerated() {
            if i > 0, app.isPreferred == false, choices[i - 1].isPreferred { sub.addItem(.separator()) }
            let item = NSMenuItem(title: app.name, action: #selector(BrowserWindowController.openWithApp(_:)), keyEquivalent: "")
            item.representedObject = app.url
            sub.addItem(item)
        }
        if !choices.isEmpty { sub.addItem(.separator()) }
        sub.addItem(MainMenu.item(CommandCatalog.spec(.openWithOther)))
        let holder = NSMenuItem(title: "Open With", action: nil, keyEquivalent: "")
        holder.submenu = sub
        return holder
    }
}
