import CoreServices
import Foundation

/// Hot reload: calls back on the main thread with the files that changed
/// anywhere under Iceberg's config folder (iceberg.toml, widget files and
/// the scripts beside them).
///
/// It uses FSEvents with file-level events, so a file saved in place (as
/// nano or `echo >>` do) is seen as well as one an editor replaces, and it
/// costs nothing while nothing changes. Saves that come in a burst are
/// gathered for `debounce` seconds and reported once.
final class ConfigWatcher {
    private let folder: URL
    private let debounce: TimeInterval
    private let onChange: @MainActor (_ paths: [String], _ rescan: Bool) -> Void
    private var stream: FSEventStreamRef?
    private var pending: Set<String> = []
    private var pendingRescan = false
    private var flush: DispatchWorkItem?

    /// Nil when FSEvents would not watch the folder (the caller falls back
    /// to `FileWatcher`).
    init?(folder: URL, debounce: TimeInterval = 0.2,
          onChange: @escaping @MainActor (_ paths: [String], _ rescan: Bool) -> Void) {
        self.folder = folder
        self.debounce = debounce
        self.onChange = onChange
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let callback: FSEventStreamCallback = { _, info, count, paths, flags, _ in
            guard let info else { return }
            let watcher = Unmanaged<ConfigWatcher>.fromOpaque(info).takeUnretainedValue()
            let array = Unmanaged<NSArray>.fromOpaque(paths).takeUnretainedValue()
            var list: [String] = []
            var rescan = false
            for i in 0..<count {
                if let path = array[i] as? String { list.append(path) }
                let f = flags[i]
                if f & FSEventStreamEventFlags(kFSEventStreamEventFlagMustScanSubDirs) != 0
                    || f & FSEventStreamEventFlags(kFSEventStreamEventFlagRootChanged) != 0 {
                    rescan = true
                }
            }
            watcher.received(list, rescan: rescan)
        }
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                           retain: nil, release: nil, copyDescription: nil)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes
                                             | kFSEventStreamCreateFlagFileEvents
                                             | kFSEventStreamCreateFlagWatchRoot)
        guard let created = FSEventStreamCreate(kCFAllocatorDefault, callback, &context,
                                                [folder.path] as CFArray,
                                                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                                0.1, flags) else { return nil }
        FSEventStreamSetDispatchQueue(created, DispatchQueue.main)
        guard FSEventStreamStart(created) else {
            FSEventStreamInvalidate(created)
            FSEventStreamRelease(created)
            return nil
        }
        stream = created
    }

    deinit {
        flush?.cancel()
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }

    /// On the main queue (the stream's dispatch queue).
    private func received(_ paths: [String], rescan: Bool) {
        pending.formUnion(paths)
        pendingRescan = pendingRescan || rescan
        flush?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let paths = Array(self.pending).sorted()
            let rescan = self.pendingRescan
            self.pending = []
            self.pendingRescan = false
            MainActor.assumeIsolated { self.onChange(paths, rescan) }
        }
        flush = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}
