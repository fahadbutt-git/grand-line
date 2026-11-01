import FileKit
import Foundation

/// Compress, as Finder does: one item becomes "Name.zip" beside it (ditto keeps
/// resource forks and tags), several become "Archive.zip" in the first item's
/// folder. Items from several folders (search results, flat view, Recents)
/// are each taken from their own folder.
///
/// The plan holds no destination: the name is claimed only when the task runs
/// (`Compressor`), so two Compress tasks queued one after the other, or a copy
/// that brings an "Archive.zip" in first, never share a name.
public struct CompressPlan: Equatable, Sendable {
    /// Where the archive goes.
    public let folder: URL
    /// The archive's name when it is free ("Name.zip", "Archive.zip"); a taken
    /// name becomes "Archive 2.zip" when the task runs.
    public let name: String
    public let items: [URL]

    public static func make(for items: [URL]) -> CompressPlan? {
        guard let first = items.first else { return nil }
        let folder = first.deletingLastPathComponent()
        let name = items.count == 1 ? first.lastPathComponent + ".zip" : "Archive.zip"
        return CompressPlan(folder: folder, name: name, items: items)
    }

    /// Names two of the items share: they would be one name at the top of the
    /// archive, so such a selection is refused.
    public var sharedNames: [String] {
        var seen = Set<String>()
        var shared: [String] = []
        for item in items {
            let key = item.lastPathComponent.lowercased()
            if !seen.insert(key).inserted { shared.append(item.lastPathComponent) }
        }
        return shared
    }

    /// The tool that writes the archive to `archive`, a file Nexus made for it.
    public func command(writingTo archive: URL) -> ToolCommand {
        if items.count == 1 {
            return ToolCommand("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", "--keepParent", items[0].path, archive.path])
        }
        // bsdtar takes "-C folder" before each name: every item is read from
        // its own folder, under its own name.
        var arguments = ["-a", "-c", "-f", archive.path]
        for item in items {
            arguments += ["-C", item.deletingLastPathComponent().path, Self.operand(item.lastPathComponent)]
        }
        return ToolCommand("/usr/bin/bsdtar", arguments)
    }

    /// A name starting with "-" would read as an option, one starting with "@"
    /// as another archive to copy in.
    static func operand(_ name: String) -> String {
        name.hasPrefix("-") || name.hasPrefix("@") ? "./" + name : name
    }
}

/// A tool's error text as an error (Compress, Empty Trash).
public struct ToolFailure: LocalizedError, Equatable {
    public let message: String

    public init(_ message: String) {
        self.message = message.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var errorDescription: String? { message.isEmpty ? "The tool failed." : message }
}

/// Runs a Compress plan inside its task. The archive's name is claimed when the
/// task starts, with an exclusive create (`FileNaming.reserve`), and the tool
/// writes to a second file of Nexus's own beside it, never to a path that
/// already held something. Once the tool has finished, the archive takes the
/// claimed name in one rename. Stop ends the tool; a half-written archive goes
/// to the Trash and the claimed name is given back.
public enum Compressor {
    @discardableResult
    public static func run(_ plan: CompressPlan, operations: FileOperations) async throws -> URL {
        if let shared = plan.sharedNames.first { throw FileOperationError.duplicateNames([shared]) }
        try Task.checkCancellation()
        let reserved = try FileNaming.reserve(plan.name, in: plan.folder)
        let working: ReservedName
        do {
            working = try FileNaming.reserve(".compressing-\(UUID().uuidString).zip", in: plan.folder)
        } catch {
            reserved.release()
            throw error
        }
        do {
            let result = try await ProcessRunner.run(plan.command(writingTo: working.url))
            guard result.succeeded else { throw ToolFailure(result.errorText) }
            try Task.checkCancellation()
            try FileNaming.settle(working.url, onto: reserved)
        } catch {
            if working.isUntouched {
                working.release()
            } else {
                await operations.discard(working.url)
            }
            reserved.release()
            throw error
        }
        await operations.recordCreated([reserved.url], kind: .compress)
        return reserved.url
    }
}
