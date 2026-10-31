import AppKit
import BrowserKit
import FileKit
import UniformTypeIdentifiers

/// Dropping files from any app (R21): within a volume they move, across
/// volumes or out of Google Drive they copy (R14); Option forces a copy.
extension BrowserModel {
    func drop(_ urls: [URL], into folder: URL, forceCopy: Bool) {
        let sources = urls.filter { $0.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL || forceCopy }
        guard !sources.isEmpty else { return }
        let moves = !forceCopy && GoogleDrive.dragOperation(from: sources, to: folder, home: services.paths.home) == .move
        let pane = panes.first { $0.location.folderURL?.standardizedFileURL == folder.standardizedFileURL }
        transfer(sources, to: folder, moving: moves, select: pane)
    }
}

/// Reads file URLs from SwiftUI drop providers.
enum FileDrop {
    /// Collects URLs from the providers' callbacks, which run on other threads.
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []

        func add(_ url: URL) {
            lock.lock()
            urls.append(url)
            lock.unlock()
        }

        var all: [URL] {
            lock.lock()
            defer { lock.unlock() }
            return urls
        }
    }

    @MainActor
    static func load(_ providers: [NSItemProvider], done: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let collected = Collected()
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                if let data, let url = URL(dataRepresentation: data, relativeTo: nil) { collected.add(url) }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated { done(collected.all) }
        }
    }
}
