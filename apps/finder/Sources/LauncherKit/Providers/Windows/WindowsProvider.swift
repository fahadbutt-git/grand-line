import Foundation

/// An open window, as AeroSpace lists it.
public struct WindowEntry: Sendable, Equatable {
    public let id: Int
    public let app: String
    public let title: String
}

/// The `<` prefix: every window AeroSpace manages, focused with `aerospace focus`.
public final class WindowsProvider: LaunchProvider, @unchecked Sendable {
    public let id = "windows"
    public let title = "Windows"
    public let symbol = "macwindow.on.rectangle"
    public let prefix: Prefix? = .windows
    public let inGlobalSearch = false
    let runner: ShellRunner
    let executable: String

    public static let format = "%{window-id}|%{app-name}|%{window-title}"

    public init(runner: ShellRunner = ShellRunner(), fileManager: FileManager = .default) {
        self.runner = runner
        self.executable = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
            .first { fileManager.isExecutableFile(atPath: $0) } ?? "/opt/homebrew/bin/aerospace"
    }

    /// Lines of "id|app|title". A title may itself contain "|".
    public static func parse(_ output: String) -> [WindowEntry] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count >= 2, let id = Int(parts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
            let app = parts[1].trimmingCharacters(in: .whitespaces)
            let title = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
            return WindowEntry(id: id, app: app, title: title)
        }
    }

    public func rows(_ windows: [WindowEntry]) -> [LaunchResult] {
        windows.map { window in
            LaunchResult(
                id: "win:\(window.id)",
                title: window.title.isEmpty ? window.app : window.title,
                subtitle: window.app,
                icon: .symbol("macwindow"),
                section: .windows,
                keywords: [window.app],
                actions: [
                    LaunchAction("Focus", symbol: "macwindow", .run(executable, arguments: ["focus", "--window-id", String(window.id)])),
                    .copy(window.title, title: "Copy title"),
                ],
                providerID: id
            )
        }
    }

    public func results(for query: LaunchQuery) async throws -> [LaunchResult] {
        let output = try await runner.run(executable, ["list-windows", "--all", "--format", Self.format], timeout: 2)
        let all = rows(Self.parse(output.stdout))
        let catalog = Catalog(all)
        return catalog.search(query.term)
    }
}
