import AppKit
import BrowserKit
import FileKit

/// Ghostty and Claude Code here (R31), transcode (R33), share and AirDrop,
/// eject and Connect to Server (R21).
extension BrowserModel {
    func openTerminal(claude: Bool) {
        guard let folder = ToolCommand.workingFolder(pane: focused.location.diskFolder, selection: focused.selectedItems) else { return }
        launch(claude ? .claude(at: folder) : .terminal(at: folder))
    }

    func transcode(_ command: BrowserCommand) {
        guard let mode = TranscodeMode.mode(for: command) else { return }
        launch(.transcode(mode, selectedOnDisk, script: services.paths.transcode))
    }

    func launch(_ command: ToolCommand) {
        do {
            try ProcessRunner.launch(command)
        } catch {
            Prompt.problem("\(command.executable) could not be started.", error)
        }
    }

    func share() {
        let urls = selectedOnDisk
        guard !urls.isEmpty, let view = window?.contentView else { return }
        let picker = NSSharingServicePicker(items: urls)
        let rect = NSRect(x: view.bounds.midX, y: view.bounds.maxY - 40, width: 1, height: 1)
        picker.show(relativeTo: rect, of: view, preferredEdge: .minY)
    }


    /// Ejects the selected volume, or the one the pane is on.
    func eject() {
        let candidates = selectedOnDisk + [focused.location.diskFolder].compactMap { $0 }
        guard let volume = candidates.lazy.compactMap({ VolumeInfo.containing($0) }).first(where: \.canEject) else {
            Prompt.problem("There is nothing here to eject.")
            return
        }
        eject(volume)
    }

    func eject(_ volume: VolumeInfo) {
        let home = services.paths.home
        let panes = self.panes
        Task {
            do {
                for pane in panes where pane.location.diskFolder.map({ VolumeInfo.containing($0)?.url == volume.url }) ?? false {
                    pane.go(.folder(home))
                }
                try await VolumeInfo.eject(volume)
            } catch {
                Prompt.problem("\(volume.name) could not be ejected.", error)
            }
        }
    }

    func eject(volumeAt url: URL) {
        guard let volume = VolumeInfo.mounted().first(where: { $0.url == url }) else { return }
        eject(volume)
    }

    /// macOS mounts the share under /Volumes; it then shows in Locations.
    func connectToServer() {
        guard let text = Prompt.text("Connect to Server", message: "For example smb://nas.local/share", value: "smb://", action: "Connect"),
              let url = ServerAddress.normalize(text) else { return }
        NSWorkspace.shared.open(url)
    }
}
