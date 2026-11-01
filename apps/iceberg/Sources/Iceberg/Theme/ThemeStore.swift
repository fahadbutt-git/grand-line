import AppIcon
import AppKit
import SwiftUI
import IcebergKit

/// The active theme, kept current: it reloads at once on the notification
/// `theme set` and `theme apply` post, and whenever the state file or a theme
/// file changes, and every view redraws from it.
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
    /// The macOS appearance last acted on (for running `theme mode` once per
    /// switch). Reloading reads the appearance fresh instead.
    private var systemIsDark = SystemStyle.isDark()
    /// `.deliverImmediately` observers: Iceberg is almost never the active
    /// app, and the block form of addObserver would hold these back until it was.
    private var appearanceObserver: DistributedObserver?
    private var changeObserver: DistributedObserver?

    init(paths: IcebergPaths) {
        self.paths = paths
        reload()
        // Not the whole state folder: Nexus rewrites a file there on every selection.
        watcher = FileWatcher(paths: [paths.themeState, paths.renderedTheme, paths.themesFolder]) { [weak self] in
            self?.reload()
        }
        changeObserver = DistributedObserver(ThemeLoader.changedNotification.rawValue) { [weak self] _ in
            self?.reload()
        }
        appearanceObserver = DistributedObserver(SystemStyle.changed.rawValue) { [weak self] _ in
            // The default is written as the notification goes out; read it a moment later.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                MainActor.assumeIsolated { self?.systemAppearanceChanged() }
            }
        }
    }

    /// macOS switched between dark and light. While the theme follows macOS
    /// the matching variant shows now, and the `theme` command switches the
    /// rest of the package (whichever app takes the lock runs it).
    private func systemAppearanceChanged() {
        let dark = SystemStyle.isDark()
        guard dark != systemIsDark else { return }
        systemIsDark = dark
        guard ThemeLoader.followsSystem(paths: paths) else { return }
        reload()
        ThemeFollowSync.run(paths: paths, systemIsDark: dark)
    }

    func reload() {
        let name = ThemeLoader.followedName(paths: paths, currentAppearanceIsDark: SystemStyle.isDark)
        let (loaded, problems) = ThemeLoader.load(paths: paths, named: name)
        if loaded != theme { theme = loaded }
        if problems != issues { issues = problems }
        // The keys Iceberg's Theme does not hold: the panel's own colours and
        // the icon's, with what the theme inherits through EXTENDS.
        let fields = ThemeLoader.resolvedFields(paths: paths, named: name)
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

/// macOS's appearance, read from the global AppleInterfaceStyle default (the
/// app's own appearance follows the theme, so it says nothing about macOS).
enum SystemStyle {
    static let changed = Notification.Name("AppleInterfaceThemeChangedNotification")

    static func isDark() -> Bool {
        CFPreferencesAppSynchronize(kCFPreferencesAnyApplication)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, kCFPreferencesAnyApplication) as? String
        return style?.lowercased() == "dark"
    }
}

/// Runs `theme mode dark|light` once after macOS switches appearance, unless
/// Nexus or Sight already is: the first app to create the lock file runs it.
enum ThemeFollowSync {
    static func run(paths: IcebergPaths, systemIsDark: Bool) {
        let current = ThemeLoader.currentName(paths: paths)
        guard ThemeLoader.variant(of: current, systemIsDark: systemIsDark, paths: paths) != nil,
              FileManager.default.isExecutableFile(atPath: paths.themeCommand.path),
              takeLock(paths.themeFollowLock) else { return }
        let lock = paths.themeFollowLock
        let process = Process()
        process.executableURL = paths.themeCommand
        process.arguments = ["mode", systemIsDark ? "dark" : "light"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { _ in try? FileManager.default.removeItem(at: lock) }
        do {
            try process.run()
        } catch {
            try? FileManager.default.removeItem(at: lock)
        }
    }

    /// Creates the lock file, unless another app made it in the last minute.
    static func takeLock(_ url: URL) -> Bool {
        if let made = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(made) > 60 {
            try? FileManager.default.removeItem(at: url)
        }
        let fd = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }
}
