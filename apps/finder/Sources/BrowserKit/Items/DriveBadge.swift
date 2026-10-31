import FileKit
import Foundation

/// Whether a Google Drive item is on this Mac or only online (R14).
public enum DriveBadge: String, Sendable, Equatable {
    case downloaded
    case online
    case downloading

    public var symbol: String {
        switch self {
        case .downloaded: return "checkmark.circle"
        case .online: return "icloud"
        case .downloading: return "arrow.down.circle"
        }
    }

    public var label: String {
        switch self {
        case .downloaded: return "On this Mac"
        case .online: return "Online only"
        case .downloading: return "Downloading"
        }
    }

    /// nil outside Google Drive, where no badge is shown.
    public static func badge(
        inDrive: Bool, status: URLUbiquitousItemDownloadingStatus?, isDownloading: Bool
    ) -> DriveBadge? {
        guard inDrive else { return nil }
        if isDownloading { return .downloading }
        if status == URLUbiquitousItemDownloadingStatus.notDownloaded { return .online }
        return .downloaded
    }

    public static func read(_ url: URL, drives: [GoogleDrive]) -> DriveBadge? {
        let inDrive = drives.contains { $0.contains(url) }
        guard inDrive else { return nil }
        let values = try? url.resourceValues(forKeys: [
            .ubiquitousItemDownloadingStatusKey, .ubiquitousItemIsDownloadingKey,
        ])
        return badge(
            inDrive: true, status: values?.ubiquitousItemDownloadingStatus,
            isDownloading: values?.ubiquitousItemIsDownloading ?? false
        )
    }
}
