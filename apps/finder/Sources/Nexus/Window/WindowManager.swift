import AppKit
import BrowserKit

/// Opens and tracks browser windows.
@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private var controllers: [BrowserWindowController] = []

    var frontModel: BrowserModel? {
        (NSApp.keyWindow?.windowController as? BrowserWindowController)?.model
            ?? (NSApp.mainWindow?.windowController as? BrowserWindowController)?.model
    }

    @discardableResult
    func newWindow(at folder: URL, select: [URL] = []) -> BrowserWindowController {
        show(BrowserModel(services: Services.shared, location: .folder(folder), select: select))
    }

    /// A window where Settings, General says new windows open.
    @discardableResult
    func newWindow(from folder: URL?) -> BrowserWindowController {
        show(BrowserModel(services: Services.shared, location: NexusPreferencesStore.shared.newWindowLocation(current: folder)))
    }

    /// Every open window's model, for settings that apply at once.
    var models: [BrowserModel] { controllers.map(\.model) }

    func newTab(from model: BrowserModel) {
        let folder = model.focused.location.diskFolder ?? Services.shared.paths.home
        let controller = BrowserWindowController(model: BrowserModel(services: Services.shared, location: .folder(folder)))
        controllers.append(controller)
        if let window = model.window, let tab = controller.window {
            window.addTabbedWindow(tab, ordered: .above)
            tab.makeKeyAndOrderFront(nil)
        } else {
            controller.showWindow(nil)
        }
    }

    func open(_ workspace: Workspace) {
        show(BrowserModel(services: Services.shared, workspace: workspace))
    }

    @discardableResult
    private func show(_ model: BrowserModel) -> BrowserWindowController {
        let controller = BrowserWindowController(model: model)
        controllers.append(controller)
        if let front = NSApp.keyWindow, let window = controller.window {
            window.setFrameTopLeftPoint(NSPoint(x: front.frame.minX + 24, y: front.frame.maxY - 24))
        }
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        return controller
    }

    /// The file viewer's requests (R19): an existing window already showing the
    /// folder is reused, otherwise a new one opens.
    func show(_ request: WindowRequest) {
        if let existing = controllers.first(where: { $0.model.focused.location.folderURL?.standardizedFileURL == request.folder.standardizedFileURL }) {
            existing.model.focused.go(.folder(request.folder), select: request.select)
            existing.window?.makeKeyAndOrderFront(nil)
        } else {
            newWindow(at: request.folder, select: request.select)
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeAll() {
        for controller in controllers { controller.window?.performClose(nil) }
    }

    func closed(_ controller: BrowserWindowController) {
        controllers.removeAll { $0 === controller }
    }

    var isEmpty: Bool { controllers.isEmpty }
}
