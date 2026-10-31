import AppIcon
import AppKit
import SwiftUI
import ThemeKit

/// The active theme (R20, R30), republished when `theme set` changes it.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var theme: Theme
    private let watcher = ThemeWatcher()
    private var task: Task<Void, Never>?

    init() {
        theme = watcher.theme
    }

    func start() {
        watcher.start()
        let themes = watcher.themes
        task = Task { [weak self] in
            for await theme in themes { self?.apply(theme) }
        }
        apply(watcher.theme)
    }

    private func apply(_ theme: Theme) {
        let iconChanged = iconTheme != theme.icon
        self.theme = theme
        let appearance = NSAppearance(named: theme.appearanceName)
        NSApp.appearance = appearance
        if iconChanged {
            iconTheme = theme.icon
            AppIconInstaller.apply(.nexus, theme: theme.icon)
        }
    }

    /// The icon colours last applied, so a theme change that leaves them
    /// alone does not redraw the icon.
    private var iconTheme: IconTheme?

    var palette: Palette { Palette(theme) }
}

/// SwiftUI colours for the theme's roles.
struct Palette {
    let background: Color
    let panel: Color
    let field: Color
    let line: Color
    let hairline: Color
    let text: Color
    let strong: Color
    let dim: Color
    let faint: Color
    let selection: Color
    let selectionText: Color
    let accent: Color
    let highlight: Color
    let chip: Color

    init(_ theme: Theme) {
        background = Color(theme.background)
        panel = Color(theme.panel)
        field = Color(theme.field)
        line = Color(theme.line)
        hairline = Color(theme.hairline)
        text = Color(theme.text)
        strong = Color(theme.strong)
        dim = Color(theme.dim)
        faint = Color(theme.faint)
        selection = Color(theme.selection)
        selectionText = Color(theme.selectionText)
        accent = Color(theme.accent)
        highlight = Color(theme.highlight)
        chip = Color(theme.chip)
    }
}
