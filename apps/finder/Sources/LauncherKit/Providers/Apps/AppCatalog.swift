import Foundation

/// The installed apps: /Applications, /System/Applications and ~/Applications,
/// two folders deep (Utilities, vendor folders, Chrome's web apps). Each opens
/// through focus-or-open, so a running app's window comes forward.
public enum AppCatalog {
    public static func folders(home: String = NSHomeDirectory()) -> [String] {
        ["/Applications", "/System/Applications", home + "/Applications", "/System/Library/CoreServices/Applications"]
    }

    /// App bundles by name; the first folder wins a name found twice.
    public static func scan(_ folders: [String], fileManager: FileManager = .default) -> [String] {
        var seen = Set<String>()
        var apps: [String] = []
        func visit(_ folder: String, depth: Int) {
            guard let names = try? fileManager.contentsOfDirectory(atPath: folder) else { return }
            for name in names.sorted() where !name.hasPrefix(".") {
                let path = folder + "/" + name
                if name.hasSuffix(".app") {
                    if seen.insert(name.lowercased()).inserted { apps.append(path) }
                } else if depth < 2 {
                    var isFolder: ObjCBool = false
                    if fileManager.fileExists(atPath: path, isDirectory: &isFolder), isFolder.boolValue { visit(path, depth: depth + 1) }
                }
            }
        }
        for folder in folders { visit(folder, depth: 1) }
        return apps
    }

    public static func result(_ path: String, paths: GrandLinePaths = GrandLinePaths()) -> LaunchResult {
        let file = (path as NSString).lastPathComponent
        let name = file.hasSuffix(".app") ? String(file.dropLast(4)) : file
        return LaunchResult(
            id: "app:" + path,
            title: name,
            subtitle: paths.abbreviate((path as NSString).deletingLastPathComponent),
            icon: .app(path),
            section: .apps,
            accessory: "App",
            actions: [
                LaunchAction("Open", symbol: "arrow.up.forward.app", .run(paths.command("focus-or-open"), arguments: [name])),
                LaunchAction("Show in Log Pose", symbol: "folder", .reveal(path)),
                LaunchAction("Copy path", symbol: "doc.on.clipboard", shortcut: KeyShortcut("c", shift: true), .copyText(path)),
                LaunchAction("Quick Look", symbol: "eye", shortcut: KeyShortcut("y"), closesWindow: false, .quickLook(path)),
                .favourite,
            ],
            previewPath: path,
            providerID: "apps"
        )
    }

    public static func provider(paths: GrandLinePaths = GrandLinePaths()) -> CatalogProvider {
        CatalogProvider(id: "apps", title: "Apps", symbol: "square.grid.2x2", globalLimit: 30) {
            scan(folders(home: paths.home)).map { result($0, paths: paths) }
        }
    }
}
