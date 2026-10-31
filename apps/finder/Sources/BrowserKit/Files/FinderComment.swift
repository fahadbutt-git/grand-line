import Foundation

/// Spotlight comments (R10), kept where Spotlight reads them: the
/// com.apple.metadata:kMDItemFinderComment extended attribute, as a binary plist.
public enum FinderComment {
    static let attribute = "com.apple.metadata:kMDItemFinderComment"

    public static func read(_ url: URL) -> String {
        let path = url.path
        let size = getxattr(path, attribute, nil, 0, 0, 0)
        guard size > 0 else { return "" }
        var data = Data(count: size)
        let read = data.withUnsafeMutableBytes { buffer in
            getxattr(path, attribute, buffer.baseAddress, size, 0, 0)
        }
        guard read == size else { return "" }
        let value = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        return value as? String ?? ""
    }

    /// An empty comment removes the attribute.
    public static func write(_ comment: String, to url: URL) throws {
        let path = url.path
        if comment.isEmpty {
            _ = removexattr(path, attribute, 0)
            return
        }
        let data = try PropertyListSerialization.data(fromPropertyList: comment, format: .binary, options: 0)
        let result = data.withUnsafeBytes { buffer in
            setxattr(path, attribute, buffer.baseAddress, data.count, 0, 0)
        }
        if result != 0 { throw CocoaError(.fileWriteUnknown) }
    }
}
