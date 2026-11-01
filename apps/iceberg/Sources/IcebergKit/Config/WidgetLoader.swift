import Foundation

/// Reads every widget file in a folder. A broken file is reported and
/// skipped, never fatal, so one typo cannot take the other widgets down.
public enum WidgetLoader {
    public struct Result: Sendable {
        public var widgets: [WidgetConfig]
        public var issues: [ConfigIssue]
        /// Files that load but say `enabled = false`, for the Settings window.
        public var disabled: [WidgetConfig] = []
        /// Widgets whose file has an error, by id, with the file's name.
        public var failed: [String: String] = [:]
    }

    /// Files larger than this are refused (a widget file is a few lines).
    public static let maxFileSize = 64 * 1024
    /// More widgets than this are not loaded; the panel has no room for them.
    public static let maxWidgets = 200

    public static func load(from folder: URL, fileManager: FileManager = .default) -> Result {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return Result(widgets: [], issues: [])
        }
        let names: [String]
        do {
            names = try fileManager.contentsOfDirectory(atPath: folder.path)
        } catch {
            return Result(widgets: [], issues: [ConfigIssue(file: folder.lastPathComponent, message: "the widgets folder cannot be read")])
        }

        var widgets: [WidgetConfig] = []
        var disabled: [WidgetConfig] = []
        var issues: [ConfigIssue] = []
        var failed: [String: String] = [:]
        var seen: [String: String] = [:]
        let files = names
            .filter { !$0.hasPrefix(".") }
            .filter { ["toml", "json"].contains(($0 as NSString).pathExtension.lowercased()) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }

        for name in files {
            let url = folder.appendingPathComponent(name)
            let id = WidgetConfig.id(forFileName: name)
            if let first = seen[id] {
                issues.append(ConfigIssue(file: name, message: "skipped: \(first) already defines the widget \"\(id)\"", severity: .warning))
                continue
            }
            if widgets.count >= maxWidgets {
                issues.append(ConfigIssue(file: name, message: "skipped: only \(maxWidgets) widgets are loaded", severity: .warning))
                continue
            }
            // Through symlinks, but only to a regular file, and capped as it
            // is read: a FIFO or /dev/zero must not freeze or fill the app.
            let data: Data
            switch SafeFileRead.read(url, limit: maxFileSize) {
            case .success(let d):
                data = d
            case .failure(.tooLarge):
                issues.append(ConfigIssue(file: name, message: "skipped: the file is larger than \(maxFileSize / 1024) KB"))
                continue
            case .failure(.notAFile):
                issues.append(ConfigIssue(file: name, message: "skipped: not a regular file",
                                          fix: "Widget files are plain text files (a symlink to one is fine)."))
                continue
            case .failure:
                issues.append(ConfigIssue(file: name, message: "the file cannot be read"))
                continue
            }
            let (config, fileIssues) = WidgetConfig.parse(data, fileName: name, file: url)
            issues += fileIssues
            if let config {
                seen[id] = name
                if config.enabled { widgets.append(config) } else { disabled.append(config) }
            } else {
                failed[id] = name
            }
        }
        // Stable: by `order`, then by file name (the order they were read in).
        let indexed = widgets.enumerated().sorted { a, b in
            a.element.order != b.element.order ? a.element.order < b.element.order : a.offset < b.offset
        }
        return Result(widgets: indexed.map(\.element), issues: issues, disabled: disabled, failed: failed)
    }
}

/// What a save in the config folder changes, worked out without touching
/// the screen, so hot reload can be tested.
public enum WidgetReload {
    /// Widgets whose file has a mistake keep their last good version until
    /// the file is fixed, so a half-typed edit does not blank the widget.
    /// Returns the widgets to use and the ids kept from before.
    public static func keepLastGood(previous: [WidgetConfig], loaded: WidgetLoader.Result) -> (widgets: [WidgetConfig], kept: [String]) {
        var widgets = loaded.widgets
        var kept: [String] = []
        let present = Set(loaded.widgets.map(\.id) + loaded.disabled.map(\.id))
        for old in previous where loaded.failed[old.id] != nil && !present.contains(old.id) {
            widgets.append(old)
            kept.append(old.id)
        }
        return (widgets, kept)
    }

    /// Ids that are new or whose file now says something different.
    public static func changed(from old: [WidgetConfig], to new: [WidgetConfig]) -> Set<String> {
        var before: [String: WidgetConfig] = [:]
        for w in old { before[w.id] = w }
        return Set(new.filter { before[$0.id] != $0 }.map(\.id))
    }

    /// Widgets that use a script that was saved: a changed file that is not
    /// a widget file, named in a widget's command or click.
    public static func affected(byChangedFiles names: [String], widgets: [WidgetConfig]) -> Set<String> {
        let scripts = names
            .filter { !["toml", "json"].contains(($0 as NSString).pathExtension.lowercased()) }
            .filter { !$0.hasPrefix(".") && !$0.isEmpty }
        guard !scripts.isEmpty else { return [] }
        var ids: Set<String> = []
        for w in widgets {
            let text = w.command + " " + (w.click ?? "")
            if scripts.contains(where: { text.contains($0) }) { ids.insert(w.id) }
        }
        return ids
    }
}
