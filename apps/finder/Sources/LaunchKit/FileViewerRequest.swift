import Foundation

/// What macOS asks of the file viewer once Log Pose is NSFileViewer and the
/// folder handler: open folders (the 'odoc' event, or application(_:open:)), or
/// reveal items, the 'misc'/'mvis' event NSWorkspace.activateFileViewerSelecting sends.
public enum FileViewerRequest: Sendable, Equatable {
    case open([URL])
    /// Show each item's folder with the item selected.
    case reveal([URL])

    static let coreEvents: UInt32 = 0x6165_7674 // 'aevt'
    static let openDocuments: UInt32 = 0x6F64_6F63 // 'odoc'
    static let miscStandards: UInt32 = 0x6D69_7363 // 'misc'
    static let makeObjectsVisible: UInt32 = 0x6D76_6973 // 'mvis'
    static let directObject: UInt32 = 0x2D2D_2D2D // '----'

    /// The Apple events to install handlers for, as (event class, event ID).
    public static let handledEvents: [(eventClass: UInt32, eventID: UInt32)] = [
        (coreEvents, openDocuments),
        (miscStandards, makeObjectsVisible),
    ]

    /// nil for any other event, or one without file items.
    public static func parse(_ event: NSAppleEventDescriptor) -> FileViewerRequest? {
        guard let direct = event.paramDescriptor(forKeyword: directObject) else { return nil }
        let urls = fileURLs(in: direct)
        guard !urls.isEmpty else { return nil }
        switch (event.eventClass, event.eventID) {
        case (coreEvents, openDocuments): return .open(urls)
        case (miscStandards, makeObjectsVisible): return .reveal(urls)
        default: return nil
        }
    }

    /// File URLs in a descriptor that holds one item or a list of them (aliases or file URLs).
    public static func fileURLs(in descriptor: NSAppleEventDescriptor) -> [URL] {
        let count = descriptor.numberOfItems
        if descriptor.descriptorType == 0x6C69_7374, count > 0 { // 'list'
            return (1...count).compactMap { descriptor.atIndex($0).flatMap(fileURL) }
        }
        return fileURL(descriptor).map { [$0] } ?? []
    }

    static func fileURL(_ descriptor: NSAppleEventDescriptor) -> URL? {
        let coerced = descriptor.coerce(toDescriptorType: 0x6675_726C) ?? descriptor // 'furl'
        return coerced.fileURLValue
    }

    /// The folder to show and the items to select in it. Items from several folders
    /// open the first item's folder; folders handed to `open` are shown themselves.
    public var target: (folder: URL, selection: [URL]) {
        switch self {
        case .open(let urls):
            return (urls[0], [])
        case .reveal(let urls):
            let folder = urls[0].deletingLastPathComponent()
            let selection = urls.filter { $0.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL }
            return (folder, selection)
        }
    }
}
