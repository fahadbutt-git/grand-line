import FileKit
import Foundation

/// Compress, as Finder does: one item becomes "Name.zip" beside it (ditto keeps
/// resource forks and tags), several become "Archive.zip".
public struct CompressPlan: Equatable, Sendable {
    public let destination: URL
    public let command: ToolCommand

    public static func make(for items: [URL]) -> CompressPlan? {
        guard let first = items.first else { return nil }
        let folder = first.deletingLastPathComponent()
        if items.count == 1 {
            let name = FileNaming.available(first.lastPathComponent + ".zip", in: folder)
            let destination = folder.appendingPathComponent(name)
            return CompressPlan(destination: destination, command: ToolCommand(
                "/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", first.path, destination.path]
            ))
        }
        let name = FileNaming.available("Archive.zip", in: folder)
        let destination = folder.appendingPathComponent(name)
        // A name starting with "-" would read as an option.
        let names = items.map { $0.lastPathComponent.hasPrefix("-") ? "./" + $0.lastPathComponent : $0.lastPathComponent }
        return CompressPlan(destination: destination, command: ToolCommand(
            "/usr/bin/bsdtar", ["-a", "-c", "-f", destination.path, "-C", folder.path] + names
        ))
    }
}
