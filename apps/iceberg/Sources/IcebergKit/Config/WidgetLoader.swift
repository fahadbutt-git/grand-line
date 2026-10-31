import Foundation

/// Reads every widget file in a folder. A broken file is reported and
/// skipped, never fatal, so one typo cannot take the other widgets down.
public enum WidgetLoader {
    public struct Result: Sendable {
        public var widgets: [WidgetConfig]
        public var issues: [ConfigIssue]
        /// Files that load but say `enabled = false`, for the Settings window.
        public var disabled: [WidgetConfig] = []
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
            let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue ?? 0
            if size > maxFileSize {
                issues.append(ConfigIssue(file: name, message: "skipped: the file is larger than \(maxFileSize / 1024) KB"))
                continue
            }
            guard let data = fileManager.contents(atPath: url.path) else {
                issues.append(ConfigIssue(file: name, message: "the file cannot be read"))
                continue
            }
            let (config, fileIssues) = WidgetConfig.parse(data, fileName: name, file: url)
            issues += fileIssues
            if let config {
                seen[id] = name
                if config.enabled { widgets.append(config) } else { disabled.append(config) }
            }
        }
        // Stable: by `order`, then by file name (the order they were read in).
        let indexed = widgets.enumerated().sorted { a, b in
            a.element.order != b.element.order ? a.element.order < b.element.order : a.offset < b.offset
        }
        return Result(widgets: indexed.map(\.element), issues: issues, disabled: disabled)
    }
}
