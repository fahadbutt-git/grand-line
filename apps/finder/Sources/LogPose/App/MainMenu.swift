import AppKit
import BrowserKit

/// The menu bar, built from BrowserKit's catalog, so every action is listed
/// with its shortcut. Items go down the responder chain to the key window.
@MainActor
enum MainMenu {
    static let commandAction = #selector(BrowserWindowController.performBrowserCommand(_:))

    static func build(workspaces: NSMenuDelegate) -> NSMenu {
        let bar = NSMenu()
        bar.addItem(submenu(appMenu()))
        for group in MenuGroup.allCases {
            let menu = NSMenu(title: group.rawValue)
            fill(menu, with: MenuLayout.entries(for: group))
            if group == .edit {
                menu.addItem(.separator())
                menu.addItem(NSMenuItem(title: "Emoji & Symbols", action: #selector(NSApplication.orderFrontCharacterPalette(_:)), keyEquivalent: ""))
            }
            bar.addItem(submenu(menu))
        }
        bar.addItem(submenu(windowMenu(workspaces: workspaces)))
        let help = NSMenu(title: "Help")
        bar.addItem(submenu(help))
        NSApp.helpMenu = help
        return bar
    }

    static func fill(_ menu: NSMenu, with entries: [MenuEntry]) {
        for entry in entries {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .command(let spec):
                add(spec, to: menu)
            case .submenu(let title, let specs):
                let sub = NSMenu(title: title)
                for spec in specs { add(spec, to: sub) }
                let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                holder.submenu = sub
                menu.addItem(holder)
            }
        }
    }

    /// The visible item with the first shortcut, then a hidden item for each
    /// further Command or Control shortcut (Cmd+Y for Quick Look, Cmd+L for Make
    /// Alias), so those work in every view. Plain extras such as Return are
    /// handled by the views themselves.
    static func add(_ spec: CommandSpec, to menu: NSMenu) {
        menu.addItem(item(spec))
        for index in spec.shortcuts.indices.dropFirst() where !spec.shortcuts[index].isPlain {
            let extra = item(spec, shortcut: index)
            extra.isHidden = true
            extra.allowsKeyEquivalentWhenHidden = true
            menu.addItem(extra)
        }
    }

    /// The item's tag is the index of its shortcut, for `TextFieldGuard`.
    static func item(_ spec: CommandSpec, shortcut index: Int = 0) -> NSMenuItem {
        let shortcut = spec.shortcuts.indices.contains(index) ? spec.shortcuts[index] : nil
        let item = NSMenuItem(title: spec.title, action: commandAction, keyEquivalent: shortcut?.menuKeyEquivalent ?? "")
        item.representedObject = spec.command.rawValue
        item.tag = index
        if let shortcut { item.keyEquivalentModifierMask = mask(shortcut.modifiers) }
        return item
    }

    static func mask(_ modifiers: Shortcut.Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }

    static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "Log Pose")
        menu.addItem(NSMenuItem(title: "About Log Pose", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(AppDelegate.openSettings(_:)), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Reload Settings", action: #selector(AppDelegate.reloadSettings(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        let servicesMenu = NSMenu(title: "Services")
        services.submenu = servicesMenu
        NSApp.servicesMenu = servicesMenu
        menu.addItem(services)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Hide Log Pose", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        let others = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(others)
        menu.addItem(NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Log Pose", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    static func windowMenu(workspaces: NSMenuDelegate) -> NSMenu {
        let menu = NSMenu(title: "Window")
        menu.addItem(NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        menu.addItem(NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""))
        menu.addItem(.separator())
        let holder = NSMenuItem(title: "Workspaces", action: nil, keyEquivalent: "")
        let list = NSMenu(title: "Workspaces")
        list.delegate = workspaces
        holder.submenu = list
        menu.addItem(holder)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: ""))
        NSApp.windowsMenu = menu
        return menu
    }

    static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }
}
