import AppKit
import BrowserKit

/// Runs a command from a menu, a key or a button, and says when it applies.
extension BrowserModel {
    var context: (inArchive: Bool, inTrash: Bool) {
        (focused.location.isArchive, focused.inTrash)
    }

    func perform(_ command: BrowserCommand) {
        switch command {
        case .newWindow: WindowManager.shared.newWindow(at: focused.location.diskFolder ?? services.paths.home)
        case .newTab: WindowManager.shared.newTab(from: self)
        case .newFolder: newFolder(withSelection: false)
        case .newFolderWithSelection: newFolder(withSelection: true)
        case .open, .openSelection: openSelection()
        case .openWithOther: openWithOther()
        case .closeWindow: window?.performClose(nil)
        case .closeAllWindows: WindowManager.shared.closeAll()
        case .getInfo, .toggleInspector: showInspector.toggle()
        case .rename: renameRequest += 1
        case .compress: compress()
        case .duplicate: duplicate()
        case .makeAlias: makeAlias()
        case .showOriginal: showOriginal()
        case .quickLook: QuickLook.shared.toggle(for: self)
        case .fullScreenPreview: QuickLook.shared.showFullScreen(for: self)
        case .moveToTrash: moveToTrash()
        case .putBack: putBack()
        case .emptyTrash: emptyTrash(asking: true)
        case .emptyTrashNow: emptyTrash(asking: false)
        case .eject: eject()
        case .extract: extract(to: nil)
        case .extractTo: extractTo()
        case .share: share()
        case .airDrop: AirDrop.send(selectedOnDisk)
        case .copyPath: copyPath()
        case .addToSidebar: addToSidebar()
        case .showAllInSidebar: services.showAllInSidebar()
        case .tagRed, .tagOrange, .tagYellow, .tagGreen, .tagBlue, .tagPurple, .tagGray: toggleTag(command)
        case .removeTags: removeTags()
        case .editTags: showInspector = true
        case .find: searchFocused = true
        case .saveSearch: saveSearch()
        case .cleanClutter: cleanClutter()
        case .undo: undo()
        case .redo: redo()
        case .cut: cut()
        case .copy: copy()
        case .paste: paste(forceMove: false)
        case .moveHere: paste(forceMove: true)
        case .selectAll: focused.updateSelection { $0.selectAll($1) }
        case .deselectAll: focused.updateSelection { selection, _ in selection.clear() }
        case .viewIcons, .viewList, .viewColumns, .viewGallery, .viewPanes: setMode(for: command)
        case .sortName, .sortKind, .sortLastOpened, .sortAdded, .sortModified, .sortCreated, .sortSize, .sortTags, .sortManual:
            sort(by: command)
        case .keepFoldersOnTop: toggleFoldersOnTop()
        case .groupNone: group(by: .none)
        case .groupKind: group(by: .kind)
        case .showViewOptions: showViewOptions.toggle()
        case .rememberView: rememberView()
        case .useAsDefaultView: useAsDefaultView()
        case .toggleHidden: toggleHidden()
        case .togglePreview: showPreview.toggle()
        case .toggleSidebar: showSidebar.toggle()
        case .toggleStatusBar: showStatusBar.toggle()
        case .toggleToolbar: showToolbar.toggle()
        case .togglePathBar: showPathBar.toggle()
        case .biggerIcons: scaleIcons(by: 1.25)
        case .smallerIcons: scaleIcons(by: 0.8)
        case .showTransfers: showTransfers.toggle()
        case .back: focused.back()
        case .forward: focused.forward()
        case .enclosingFolder: focused.up()
        case .enclosingFolderInNewWindow: openEnclosingInNewWindow()
        case .goRecents: focused.go(.recents)
        case .goDocuments: goHomeFolder("Documents")
        case .goDesktop: goHomeFolder("Desktop")
        case .goDownloads: goHomeFolder("Downloads")
        case .goHome: focused.go(.folder(services.paths.home))
        case .goComputer: focused.go(.folder(URL(fileURLWithPath: "/Volumes", isDirectory: true)))
        case .goAirDrop: AirDrop.openWindow()
        case .goNetwork: goNetwork()
        case .goICloud: goHomeFolder("Library/Mobile Documents/com~apple~CloudDocs")
        case .goApplications: focused.go(.folder(URL(fileURLWithPath: "/Applications", isDirectory: true)))
        case .goUtilities: focused.go(.folder(URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true)))
        case .goLibrary: goHomeFolder("Library")
        case .goDrive: goDrive()
        case .goTrash: focused.go(.folder(services.paths.trash))
        case .goToFolder: beginPathEditing()
        case .connectToServer: connectToServer()
        case .nextPane: nextPane(forward: true)
        case .previousPane: nextPane(forward: false)
        case .copyToNextPane: transferToNextPane(moving: false)
        case .moveToNextPane: transferToNextPane(moving: true)
        case .onePane: setPaneCount(1)
        case .twoPanes: setPaneCount(2)
        case .threePanes: setPaneCount(3)
        case .fourPanes: setPaneCount(4)
        case .pinWindow: togglePin()
        case .saveWorkspace: saveWorkspace()
        case .openTerminal: openTerminal(claude: false)
        case .openClaude: openTerminal(claude: true)
        case .transcodeVideo, .transcodePNG, .transcodeJPEG, .transcodePDF, .transcodeText: transcode(command)
        }
    }

    func isEnabled(_ command: BrowserCommand) -> Bool {
        let spec = CommandCatalog.spec(command)
        guard spec.context.matches(inArchive: context.inArchive, inTrash: context.inTrash) else { return false }
        let selection = focused.selectedItems
        let onDisk = selection.filter { !$0.isInArchive }
        let folder = focused.location.folderURL
        switch command {
        case .open, .openSelection, .quickLook, .fullScreenPreview, .copyPath, .share, .airDrop:
            return !selection.isEmpty
        case .openWithOther, .compress, .duplicate, .makeAlias, .moveToTrash, .cut, .removeTags, .editTags,
             .tagRed, .tagOrange, .tagYellow, .tagGreen, .tagBlue, .tagPurple, .tagGray:
            return !onDisk.isEmpty
        case .rename:
            return onDisk.count == 1
        case .showOriginal:
            return onDisk.count == 1 && onDisk[0].isAlias
        case .putBack:
            return services.trashLedger.canPutBack(onDisk.map(\.url))
        case .newFolder, .newFolderWithSelection, .paste, .moveHere, .cleanClutter:
            return folder != nil
        case .extract, .extractTo:
            return !selection.isEmpty
        case .copyToNextPane, .moveToNextPane:
            return layout.nextPane != nil && !selection.isEmpty
        case .nextPane, .previousPane:
            return layout.count > 1 && mode == .panes
        case .undo:
            return services.undoTitle != nil
        case .redo:
            return services.redoTitle != nil
        case .addToSidebar:
            return sidebarCandidate != nil
        case .back:
            return focused.state.history.canGoBack
        case .forward:
            return focused.state.history.canGoForward
        case .enclosingFolder, .enclosingFolderInNewWindow:
            return focused.location.parent != nil
        case .showAllInSidebar:
            return services.sidebarHidden != SidebarHidden()
        case .goDrive:
            return !services.sidebar.groups.isEmpty
        case .saveSearch:
            if case .search = focused.location { return true }
            return false
        case .transcodeVideo, .transcodePNG, .transcodeJPEG, .transcodePDF, .transcodeText:
            return TranscodeMode.mode(for: command)?.accepts(selection) ?? false
        default:
            return true
        }
    }

    /// The menu title, where it changes with the state ("Undo Copy", "Hide Sidebar").
    func title(for command: BrowserCommand) -> String {
        let title = CommandCatalog.spec(command).title
        switch command {
        case .undo: return services.undoTitle ?? title
        case .redo: return services.redoTitle ?? title
        case .toggleToolbar: return showToolbar ? "Hide Toolbar" : title
        case .togglePathBar: return showPathBar ? "Hide Path Bar" : title
        case .showViewOptions: return showViewOptions ? "Hide View Options" : title
        case .toggleSidebar: return showSidebar ? "Hide Sidebar" : title
        case .togglePreview: return showPreview ? "Hide Preview" : title
        case .toggleInspector: return showInspector ? "Hide Inspector" : title
        case .toggleStatusBar: return showStatusBar ? "Hide Status Bar" : title
        case .toggleHidden: return showHidden ? "Hide Hidden Files" : title
        case .pinWindow: return pinned ? "Unpin Window" : title
        default: return title
        }
    }

    /// A tick beside the current view and sort.
    func isChecked(_ command: BrowserCommand) -> Bool {
        let order = focused.state.settings.sort
        let sort = order.field
        switch command {
        case .viewIcons: return mode == .icons
        case .viewList: return mode == .list
        case .viewColumns: return mode == .columns
        case .viewGallery: return mode == .gallery
        case .viewPanes: return mode == .panes
        case .sortName: return sort == .name
        case .sortKind: return sort == .kind
        case .sortLastOpened: return sort == .lastOpened
        case .sortAdded: return sort == .added
        case .sortTags: return sort == .tags
        case .sortModified: return sort == .modified
        case .sortCreated: return sort == .created
        case .sortSize: return sort == .size
        case .sortManual: return sort == .manual
        case .keepFoldersOnTop: return order.foldersFirst
        case .groupNone: return order.grouping == .none
        case .groupKind: return order.grouping == .kind
        case .onePane: return layout.count == 1
        case .twoPanes: return layout.count == 2
        case .threePanes: return layout.count == 3
        case .fourPanes: return layout.count == 4
        default: return false
        }
    }
}
