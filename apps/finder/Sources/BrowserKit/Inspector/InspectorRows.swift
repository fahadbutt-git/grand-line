import FileKit
import Foundation

/// The inspector (R10): one panel for any selection, from FileKit's SelectionSummary.
public struct InspectorRow: Hashable, Sendable {
    public let label: String
    public let value: String
}

public enum InspectorRows {
    /// "3 items selected", or the name for one item.
    public static func title(_ summary: SelectionSummary, single: FileItem?) -> String {
        if summary.count == 1, let single { return single.name }
        return ItemFormat.count(summary.count) + " selected"
    }

    /// "18.6 MB in total".
    public static func size(_ summary: SelectionSummary) -> String {
        ItemFormat.size(summary.totalBytes) + (summary.count > 1 ? " in total" : "")
    }

    public static func rows(_ summary: SelectionSummary, home: URL, now: Date = Date()) -> [InspectorRow] {
        var rows: [InspectorRow] = []
        let kinds = summary.kinds.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }.map(\.key)
        if !kinds.isEmpty { rows.append(InspectorRow(label: "Kinds", value: kinds.joined(separator: ", "))) }
        if let parent = summary.commonParent {
            let where_ = PathSegments.segments(for: parent, home: home).map(\.title).joined(separator: " › ")
            rows.append(InspectorRow(label: "Where", value: where_))
        }
        if let oldest = summary.oldest {
            rows.append(InspectorRow(label: summary.count == 1 ? "Modified" : "Oldest", value: ItemFormat.date(oldest, now: now)))
        }
        if summary.count > 1, let newest = summary.newest {
            rows.append(InspectorRow(label: "Newest", value: ItemFormat.date(newest, now: now)))
        }
        if summary.folders > 0 {
            rows.append(InspectorRow(label: "Contents", value: "\(ItemFormat.count(summary.files, "file")), \(ItemFormat.count(summary.folders, "folder"))"))
        }
        return rows
    }
}
