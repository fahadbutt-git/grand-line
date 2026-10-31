import Foundation

/// A mounted volume, as the sidebar and the status bar show it.
public struct VolumeInfo: Sendable, Equatable, Identifiable {
    public let url: URL
    public let name: String
    public let totalBytes: Int64
    /// Free space including purgeable space (what Finder shows as available).
    public let availableBytes: Int64
    /// Free space without purgeable space.
    public let freeBytes: Int64
    public let isRemovable: Bool
    public let isEjectable: Bool
    public let isNetwork: Bool
    public let isInternal: Bool
    public let isRoot: Bool
    public let format: String?

    public var id: URL { url }

    public init(
        url: URL, name: String, totalBytes: Int64, availableBytes: Int64, freeBytes: Int64,
        isRemovable: Bool, isEjectable: Bool, isNetwork: Bool, isInternal: Bool, isRoot: Bool, format: String?
    ) {
        self.url = url
        self.name = name
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.freeBytes = freeBytes
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isNetwork = isNetwork
        self.isInternal = isInternal
        self.isRoot = isRoot
        self.format = format
    }

    public var canEject: Bool { !isRoot && (isEjectable || isRemovable || isNetwork) }

    public enum Failure: Error, Equatable {
        case notEjectable(String)
    }

    static let keys: [URLResourceKey] = [
        .volumeNameKey, .volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
        .volumeAvailableCapacityForImportantUsageKey, .volumeIsRemovableKey, .volumeIsEjectableKey,
        .volumeIsLocalKey, .volumeIsInternalKey, .volumeIsRootFileSystemKey, .volumeLocalizedFormatDescriptionKey,
    ]

    /// Every mounted volume that Finder would show.
    public static func mounted() -> [VolumeInfo] {
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { Self.read($0) }
    }

    /// The volume holding a file or folder, for "12 GB available" in the status bar.
    public static func containing(_ url: URL) -> VolumeInfo? {
        guard let volume = try? url.resourceValues(forKeys: [.volumeURLKey]).volume else { return nil }
        return Self.read(volume)
    }

    static func read(_ url: URL) -> VolumeInfo? {
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else { return nil }
        let available = values.volumeAvailableCapacityForImportantUsage ?? Int64(values.volumeAvailableCapacity ?? 0)
        return VolumeInfo(
            url: url,
            name: values.volumeLocalizedName ?? values.volumeName ?? url.lastPathComponent,
            totalBytes: Int64(values.volumeTotalCapacity ?? 0),
            availableBytes: available,
            freeBytes: Int64(values.volumeAvailableCapacity ?? 0),
            isRemovable: values.volumeIsRemovable ?? false,
            isEjectable: values.volumeIsEjectable ?? false,
            isNetwork: !(values.volumeIsLocal ?? true),
            isInternal: values.volumeIsInternal ?? false,
            isRoot: values.volumeIsRootFileSystem ?? false,
            format: values.volumeLocalizedFormatDescription
        )
    }

    /// Unmounts the volume, and ejects the disk it is on unless it is a network volume.
    public static func eject(_ volume: VolumeInfo) async throws {
        guard volume.canEject else { throw Failure.notEjectable(volume.name) }
        let options: FileManager.UnmountOptions = volume.isNetwork ? [] : [.allPartitionsAndEjectDisk]
        let url = volume.url
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            FileManager.default.unmountVolume(at: url, options: options) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}
