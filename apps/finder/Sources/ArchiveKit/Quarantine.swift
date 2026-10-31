import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// The quarantine flag (`com.apple.quarantine`) macOS puts on downloads. Items
/// taken out of a quarantined archive get the archive's flag, as Archive
/// Utility does, so Gatekeeper still checks an app or script that came in a
/// downloaded zip (security note L1).
public enum Quarantine {
    public static let attribute = "com.apple.quarantine"

    /// The flag's raw value on an item, nil when it has none.
    public static func value(of url: URL) -> Data? {
        url.withUnsafeFileSystemRepresentation { path -> Data? in
            guard let path else { return nil }
            let size = getxattr(path, attribute, nil, 0, 0, XATTR_NOFOLLOW)
            guard size > 0 else { return nil }
            var data = Data(count: size)
            let read = data.withUnsafeMutableBytes { buffer in
                getxattr(path, attribute, buffer.baseAddress, size, 0, XATTR_NOFOLLOW)
            }
            guard read > 0 else { return nil }
            return data.prefix(read)
        }
    }

    /// Sets the flag on one item. Returns whether it was set.
    @discardableResult
    public static func set(_ value: Data, on url: URL) -> Bool {
        url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            let status = value.withUnsafeBytes { buffer in
                setxattr(path, attribute, buffer.baseAddress, value.count, 0, XATTR_NOFOLLOW)
            }
            return status == 0
        }
    }

    /// Sets the flag on an item and, for a folder, on everything inside it.
    public static func apply(_ value: Data, to url: URL) {
        set(value, on: url)
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: []) else { return }
        for case let child as URL in walker {
            set(value, on: child)
        }
    }

    /// Gives `items` the flag `source` carries; nothing happens when it has none.
    public static func copy(from source: URL, to items: [URL]) {
        guard let value = value(of: source) else { return }
        for item in items { apply(value, to: item) }
    }
}
