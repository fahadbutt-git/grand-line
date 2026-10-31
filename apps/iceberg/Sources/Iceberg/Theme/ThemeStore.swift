import AppIcon
import AppKit
import SwiftUI
import IcebergKit

/// The active theme, kept current: it reloads whenever `theme pick` writes
/// the state file or a theme file changes, and every view redraws from it.
@MainActor
final class ThemeStore: ObservableObject {
    @Published private(set) var theme: Theme = .graphite
    @Published private(set) var issues: [ConfigIssue] = []
    /// The open panel's surface, chip and line colours (NOTCH_* keys).
    @Published private(set) var notch = NotchPalette(fields: [:], theme: .graphite)
    /// The app icon's colours, applied when they change.
    private var iconTheme: IconTheme?

    private let paths: IcebergPaths
    private var watcher: FileWatcher?

    init(paths: IcebergPaths) {
        self.paths = paths
        reload()
        // Not the whole state folder: Nexus rewrites a file there on every selection.
        watcher = FileWatcher(paths: [paths.themeState, paths.renderedTheme, paths.themesFolder]) { [weak self] in
            self?.reload()
        }
    }

    func reload() {
        let (loaded, problems) = ThemeLoader.load(paths: paths)
        if loaded != theme { theme = loaded }
        if problems != issues { issues = problems }
        // The keys Iceberg's Theme does not hold: the panel's own colours and the icon's.
        let file = paths.themeFile(named: ThemeLoader.currentName(paths: paths))
        let fields = (try? String(contentsOf: file, encoding: .utf8)).map(ThemeLoader.fields) ?? [:]
        let palette = NotchPalette(fields: fields, theme: loaded)
        if palette != notch { notch = palette }
        // Without a file (a built-in theme) the icon keeps the bundled colours.
        let icon = fields.isEmpty ? IconTheme.bundled : IconTheme(values: fields)
        if icon != iconTheme {
            iconTheme = icon
            AppIconInstaller.apply(.iceberg, theme: icon)
        }
    }

    // Shorthands for views.
    var background: Color { theme.background.color }
    var foreground: Color { theme.foreground.color }
    var muted: Color { theme.muted.color }
    var highlight: Color { theme.highlight.color }
    var selection: Color { theme.selection.color }
    var raised: Color { theme.backgroundLighter.color }
    var hairline: Color { theme.selection.color }
    /// The open panel below the camera band.
    var panel: Color { notch.panel.color }
    /// Chips and raised things in the open panel.
    var card: Color { notch.card.color }
    /// Dividers between the panel's columns.
    var line: Color { notch.line.color }
    var colorScheme: ColorScheme { theme.mode == .light ? .light : .dark }

    func color(_ c: WidgetColor?) -> Color? {
        c.map { theme.resolve($0).color }
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}
