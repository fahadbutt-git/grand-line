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

    /// File promises dropped on a folder (a Mail attachment, a photo from
    /// Photos, an image from Safari, an item from an archive pane): the other
    /// app writes them into a hidden folder beside `folder`, on its volume,
    /// and a task then moves each in under a free name. Undo moves them to the
    /// Trash; one that did not arrive leaves nothing behind but the Trash.
    func receive(_ promises: [NSFilePromiseReceiver], into folder: URL) {
        let staging = folder.appendingPathComponent(".receiving-\(UUID().uuidString)", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        } catch {
            Prompt.problem("The items could not be received here.", error)
            return
        }
        let expected = promises.reduce(0) { $0 + max(1, $1.fileTypes.count) }
        PromiseDrop.receive(promises, at: staging, expected: expected) { [weak self] received, failure in
            guard let self else { return }
            let services = self.services
            let pane = self.panes.first { $0.location.folderURL?.standardizedFileURL == folder.standardizedFileURL } ?? self.focused
            Task {
                guard !received.isEmpty else {
                    await services.operations.discardWorkingFolder(staging)
                    Prompt.problem("The items could not be received here.", failure)
                    return
                }
                do {
                    let made = try await services.run(.copy, TaskTitles.title(.copy, received, to: folder)) { operations in
                        let made = try await operations.adopt(received, into: folder)
                        await operations.discardWorkingFolder(staging)
                        return made
                    }
                    if pane.location.folderURL?.standardizedFileURL == folder.standardizedFileURL { pane.go(.folder(folder), select: made) }
                } catch is CancellationError {
                    await services.operations.discardWorkingFolder(staging)
                } catch {
                    await services.operations.discardWorkingFolder(staging)
                    Prompt.problem("The items could not be received here.", error)
                }
                services.refreshUndo()
            }
        }
    }
}

/// Collects what file promises wrote, on AppKit's queue, and calls back on the
/// main thread once every file arrived or failed (or after a minute).
enum PromiseDrop {
    private final class Collected: @unchecked Sendable {
        private let lock = NSLock()
        private var urls: [URL] = []
        private var failure: Error?
        private var count = 0
        private var finished = false
        let expected: Int
        let done: @MainActor ([URL], Error?) -> Void

        init(expected: Int, done: @escaping @MainActor ([URL], Error?) -> Void) {
            self.expected = expected
            self.done = done
        }

        func add(_ url: URL, _ error: Error?) {
            lock.lock()
            if let error { failure = error } else { urls.append(url) }
            count += 1
            let complete = count >= expected
            lock.unlock()
            if complete { finish() }
        }

        func finish() {
            lock.lock()
            guard !finished else { lock.unlock(); return }
            finished = true
            let urls = self.urls
            let failure = self.failure
            lock.unlock()
            DispatchQueue.main.async { MainActor.assumeIsolated { self.done(urls, failure) } }
        }
    }

    private static let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    @MainActor
    static func receive(_ promises: [NSFilePromiseReceiver], at folder: URL, expected: Int,
                        done: @escaping @MainActor ([URL], Error?) -> Void) {
        let collected = Collected(expected: expected, done: done)
        for promise in promises {
            promise.receivePromisedFiles(atDestination: folder, options: [:], operationQueue: queue) { url, error in
                collected.add(url, error)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { collected.finish() }
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
