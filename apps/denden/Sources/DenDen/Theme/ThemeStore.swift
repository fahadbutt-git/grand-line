import AppKit
import SwiftUI
import DenDenKit

/// The active theme, kept current: it reloads whenever `theme pick` writes
/// the state file or a theme file changes, and every view redraws from it.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var theme: Theme = .graphite
    @Published private(set) var issues: [ConfigIssue] = []

    private let paths: DenDenPaths
    private var watcher: FileWatcher?

    init(paths: DenDenPaths) {
        self.paths = paths
        reload()
        // Not the whole state folder: Log Pose rewrites a file there on every selection.
        watcher = FileWatcher(paths: [paths.themeState, paths.renderedTheme, paths.themesFolder]) { [weak self] in
            self?.reload()
        }
    }

    func reload() {
        let (loaded, problems) = ThemeLoader.load(paths: paths)
        if loaded != theme { theme = loaded }
        if problems != issues { issues = problems }
    }

    // Shorthands for views.
    var background: Color { theme.background.color }
    var foreground: Color { theme.foreground.color }
    var muted: Color { theme.muted.color }
    var highlight: Color { theme.highlight.color }
    var selection: Color { theme.selection.color }
    var raised: Color { theme.backgroundLighter.color }
    var hairline: Color { theme.selection.color }
    var colorScheme: ColorScheme { theme.mode == .light ? .light : .dark }

    func color(_ c: WidgetColor?) -> Color? {
        c.map { theme.resolve($0).color }
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}
