import IndexKit
import SwiftUI

/// The name index's state for a Settings pane, read through IndexKit's
/// `IndexStatusProviding` (the shared index service in both apps), and its
/// Rebuild button.
@MainActor
public final class IndexStatusModel: ObservableObject {
    @Published public private(set) var status: IndexStatus?
    @Published public private(set) var rebuilding = false
    private let provider: @MainActor () -> (any IndexStatusProviding)?

    public init(provider: @escaping @MainActor () -> (any IndexStatusProviding)?) {
        self.provider = provider
    }

    public var isAvailable: Bool { provider() != nil }

    public func refresh() async {
        guard let index = provider() else { return }
        let fresh = await index.status()
        if fresh != status { status = fresh }
    }

    public func rebuild() {
        guard !rebuilding, let index = provider() else { return }
        rebuilding = true
        Task { [weak self] in
            await index.rebuild()
            await self?.refresh()
            self?.rebuilding = false
        }
    }
}

public struct IndexStatusSection: View {
    @EnvironmentObject private var theme: SettingsTheme
    @ObservedObject var model: IndexStatusModel
    @Environment(\.settingsWindowVisible) private var windowVisible
    let idPrefix: String
    let allowsRebuild: Bool
    let home: String

    public init(model: IndexStatusModel, idPrefix: String, allowsRebuild: Bool = true,
                home: String = FileManager.default.homeDirectoryForCurrentUser.path) {
        self.model = model
        self.idPrefix = idPrefix
        self.allowsRebuild = allowsRebuild
        self.home = home
    }

    public var body: some View {
        SettingsSection("Name index", note: "File names come from the Grand Line index, which Nexus and Sight share. Contents come from Spotlight.") {
            if let status = model.status {
                SettingsRow("Files and folders indexed") {
                    Text(status.files.formatted())
                        .font(.system(size: 13).monospacedDigit())
                        .foregroundStyle(theme.text)
                        .accessibilityIdentifier("\(idPrefix).settings.index.count")
                }
                SettingsRow("Last in step with the disk") {
                    Text(status.lastSync.map { $0.formatted(.relative(presentation: .named)) } ?? "Not yet")
                        .font(.system(size: 13))
                        .foregroundStyle(theme.text)
                }
                SettingsRow("State", detail: status.source == .service ? "From the index service." : "From this app's copy while the service is out of reach.") {
                    Text(state(status)).font(.system(size: 13)).foregroundStyle(theme.text)
                }
                if let problem = status.problem {
                    SettingsRow("Index service not used", detail: problem)
                }
                if !status.roots.isEmpty {
                    SettingsRow("Covers", detail: status.roots.map(abbreviate).joined(separator: ", "))
                }
                if !status.unreadable.isEmpty {
                    SettingsRow("\(status.unreadable.count) folders macOS would not let it read",
                                detail: status.unreadable.prefix(3).map(abbreviate).joined(separator: ", "))
                }
            } else {
                SettingsRow(model.isAvailable ? "Reading the index…" : "The index cannot be reached.")
            }
            if allowsRebuild {
                SettingsRow("Rebuild the index", detail: "Walks every folder again. Searching keeps working meanwhile.") {
                    HStack(spacing: 8) {
                        if model.rebuilding || (model.status?.building ?? false) { ProgressView().controlSize(.small) }
                        Button("Rebuild Index") { model.rebuild() }
                            .disabled(model.rebuilding || !model.isAvailable)
                            .accessibilityIdentifier("\(idPrefix).settings.index.rebuild")
                    }
                }
            }
        }
        // Fresh every two seconds while the window is on screen, and not at
        // all while it is closed, minimised or covered.
        .task(id: windowVisible) {
            guard windowVisible else { return }
            while !Task.isCancelled {
                await model.refresh()
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func state(_ status: IndexStatus) -> String {
        if status.building { return "Building" }
        return status.complete ? "Up to date" : "Partly built"
    }

    private func abbreviate(_ path: String) -> String {
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
        return path
    }
}
