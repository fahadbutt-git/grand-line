import FileKit
import Foundation

/// What a task is called in the tasks popover: "Copy 3 items to Documents",
/// "Move report.pdf to the Trash".
public enum TaskTitles {
    public static func title(_ kind: FileOperationKind, _ items: [URL], to folder: URL? = nil) -> String {
        let what = items.count == 1 ? items[0].lastPathComponent : ItemFormat.count(items.count)
        let place = folder.map { " to " + name(of: $0) } ?? ""
        switch kind {
        case .copy: return "Copy \(what)" + place
        case .move: return "Move \(what)" + place
        case .duplicate: return "Duplicate \(what)"
        case .rename, .renameItems: return "Rename \(what)"
        case .newFolder: return "New folder" + (folder.map { " in " + name(of: $0) } ?? "")
        case .trash: return "Move \(what) to the Trash"
        case .compress: return "Compress \(what)"
        case .extract: return "Extract \(what)" + place
        case .putBack: return "Put back \(what)"
        }
    }

    /// One line of the undo history: "Copy: report.pdf", "Move to Trash: 3 items".
    public static func history(_ record: OperationRecord) -> String {
        let what = record.count == 1 ? (record.names.first ?? ItemFormat.count(1)) : ItemFormat.count(record.count)
        return record.kind.rawValue + ": " + what
    }

    /// The Finder name: "Trash", not ".Trash"; "/" for the disk root.
    static func name(of folder: URL) -> String {
        let last = folder.standardizedFileURL.lastPathComponent
        if last == ".Trash" { return "the Trash" }
        return last.isEmpty ? "/" : last
    }
}
