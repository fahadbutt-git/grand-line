import AppKit
import ThemeKit

/// The active theme, published again when `theme set` changes it.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var theme: Theme
    private let watcher = ThemeWatcher()
    private var task: Task<Void, Never>?

    init() {
        theme = watcher.theme
        watcher.start()
        let themes = watcher.themes
        task = Task { [weak self] in
            for await theme in themes { self?.theme = theme }
        }
    }
}
