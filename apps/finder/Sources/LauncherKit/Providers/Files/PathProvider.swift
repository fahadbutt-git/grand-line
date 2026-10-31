import Foundation

/// Text starting with ~/ or / is a path: the folder's entries that start with
/// the last part are listed, and Tab completes the selected one.
public struct PathProvider: InstantProvider {
    public let id = "path"
    public let title = "Paths"
    public let symbol = "folder"
    public let prefix: Prefix? = nil
    public let inGlobalSearch = false
    public let handlesPaths = true
    let paths: GrandLinePaths
    let showsHidden: Bool

    public init(paths: GrandLinePaths = GrandLinePaths(), showsHidden: Bool = false) {
        self.paths = paths
        self.showsHidden = showsHidden
    }

    /// The folder to list and the start of the name typed so far.
    public static func split(_ path: String) -> (folder: String, partial: String) {
        if path.hasSuffix("/") { return (path, "") }
        let folder = (path as NSString).deletingLastPathComponent
        return (folder.isEmpty ? "/" : folder, (path as NSString).lastPathComponent)
    }

    public func instantResults(for query: LaunchQuery) -> [LaunchResult] {
        let typed = query.term
        let full = paths.expand(typed)
        let (folder, partial) = Self.split(full)
        let fileManager = FileManager.default
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder) else { return [] }
        let lowered = partial.lowercased()
        let typedFolder = typed.hasSuffix("/") ? typed : (typed as NSString).deletingLastPathComponent + "/"
        var rows: [LaunchResult] = []
        var exact: LaunchResult?
        for name in names.sorted(by: { $0.localizedStandardCompare($1) == .orderedAscending }) {
            if name.hasPrefix("."), !showsHidden, !partial.hasPrefix(".") { continue }
            if name == ".DS_Store" || name.hasPrefix("._") { continue }
            guard lowered.isEmpty || name.lowercased().hasPrefix(lowered) else { continue }
            let path = (folder as NSString).appendingPathComponent(name)
            var isFolder: ObjCBool = false
            _ = fileManager.fileExists(atPath: path, isDirectory: &isFolder)
            let hit = FileHit(path: path, isFolder: isFolder.boolValue, tier: name.lowercased() == lowered ? .exact : .prefix,
                              highlights: [0..<partial.utf16.count])
            var row = FileResults.result(hit, paths: paths)
            row.section = .files
            row.subtitle = paths.abbreviate(folder)
            row.actions.insert(LaunchAction.complete(typedFolder + name + (isFolder.boolValue ? "/" : "")), at: row.actions.count - 1)
            if hit.tier == .exact { exact = row } else { rows.append(row) }
            if rows.count >= 200 { break }
        }
        return (exact.map { [$0] } ?? []) + rows
    }
}
