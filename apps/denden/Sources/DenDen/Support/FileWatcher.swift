import Foundation

/// Calls back on the main thread when any of a few files or folders change.
/// It uses kernel file events (kqueue through DispatchSource), so it costs
/// nothing while nothing changes. A path that does not exist yet is watched
/// through its nearest existing parent, and every change re-arms the watch,
/// which follows files that editors and `theme pick` replace rather than edit.
final class FileWatcher {
    private let paths: [URL]
    private let debounce: TimeInterval
    private let onChange: @MainActor () -> Void
    private var sources: [DispatchSourceFileSystemObject] = []
    private var pending: DispatchWorkItem?

    init(paths: [URL], debounce: TimeInterval = 0.25, onChange: @escaping @MainActor () -> Void) {
        self.paths = paths
        self.debounce = debounce
        self.onChange = onChange
        arm()
    }

    deinit {
        pending?.cancel()
        for s in sources { s.cancel() }
    }

    private func arm() {
        for s in sources { s.cancel() }
        sources = []
        var watched = Set<String>()
        for url in paths {
            let target = Self.nearestExisting(url)
            guard watched.insert(target.path).inserted else { continue }
            let fd = open(target.path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: fd, eventMask: [.write, .delete, .rename, .extend, .attrib, .link], queue: .main)
            source.setEventHandler { [weak self] in self?.changed() }
            source.setCancelHandler { close(fd) }
            source.resume()
            sources.append(source)
        }
    }

    private func changed() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.arm()
            MainActor.assumeIsolated { self.onChange() }
        }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    static func nearestExisting(_ url: URL) -> URL {
        var current = url.standardizedFileURL
        while !FileManager.default.fileExists(atPath: current.path), current.pathComponents.count > 1 {
            current.deleteLastPathComponent()
        }
        return current
    }
}
