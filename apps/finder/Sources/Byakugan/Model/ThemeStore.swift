import AppIcon
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
            for await theme in themes { self?.apply(theme) }
        }
        applyIcon(theme)
    }

    private func apply(_ theme: Theme) {
        self.theme = theme
        applyIcon(theme)
    }

    /// The app icon (Dock, Finder) in the theme's colours, redrawn only when they change.
    private var iconTheme: IconTheme?
    private func applyIcon(_ theme: Theme) {
        guard iconTheme != theme.icon else { return }
        iconTheme = theme.icon
        AppIconInstaller.apply(.byakugan, theme: theme.icon)
    }
}
