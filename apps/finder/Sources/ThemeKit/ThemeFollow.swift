import Foundation

/// Dark, light, or whichever macOS shows: the Appearance setting every app
/// offers. Dark and light name a variant of the current family; following
/// macOS swaps between them as the system appearance changes.
public enum ThemeAppearance: String, Sendable, CaseIterable {
    case dark
    case light
    case system

    public var title: String {
        switch self {
        case .dark: return "Dark"
        case .light: return "Light"
        case .system: return "Follow macOS"
        }
    }
}

/// Which variant of a theme matches the system appearance, by the same rules
/// as `theme set FAMILY` and `theme mode`: a FAMILY= pair is FAMILY-dark and
/// FAMILY-light, and Graphite and Daylight pair up.
public enum ThemeFollow {
    public static let systemFamily = "system"
    public static let systemPair: Set<String> = ["graphite", "daylight"]

    /// The theme to switch to so `current` matches the system, or nil when it
    /// already does or has no variant for that appearance.
    /// - Parameters:
    ///   - family: the theme's FAMILY= (`systemFamily` for Graphite and Daylight).
    ///   - exists: whether a theme of that name can be loaded.
    public static func variant(of current: String, systemIsDark: Bool, family: String?,
                               exists: (String) -> Bool) -> String? {
        let target: String
        switch family {
        case nil, "":
            return nil
        case systemFamily?:
            target = systemIsDark ? "graphite" : "daylight"
        case let family?:
            target = family + (systemIsDark ? "-dark" : "-light")
        }
        guard target != current, exists(target) else { return nil }
        return target
    }

    /// The arguments for `theme mode` that bring the active theme to the system's appearance.
    public static func modeArguments(systemIsDark: Bool) -> [String] {
        ["mode", systemIsDark ? "dark" : "light"]
    }

    /// After macOS switches appearance: if the theme follows it and is not in
    /// the matching variant, run `theme mode dark|light` once, so the
    /// terminal, menus and every app change together. Several apps call this at
    /// the same moment; the first to take the lock file runs the command.
    /// Returns whether this call ran it.
    @discardableResult
    public static func switchIfNeeded(location: ThemeLocation, systemIsDark: Bool) async -> Bool {
        guard location.followsSystem() else { return false }
        let current = location.activeName() ?? ThemeLocation.fallbackName
        let exists: (String) -> Bool = { FileManager.default.fileExists(atPath: location.file(named: $0).path) }
        guard variant(of: current, systemIsDark: systemIsDark, family: location.family(of: current), exists: exists) != nil,
              FileManager.default.isExecutableFile(atPath: location.themeCommand.path),
              takeLock(location.followLock) else { return false }
        defer { try? FileManager.default.removeItem(at: location.followLock) }
        _ = await ThemeCommand.run(modeArguments(systemIsDark: systemIsDark), location: location)
        return true
    }

    /// Creates the lock file, unless another app made it in the last minute.
    static func takeLock(_ url: URL, now: Date = Date()) -> Bool {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let made = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date,
           now.timeIntervalSince(made) > 60 {
            try? FileManager.default.removeItem(at: url)
        }
        let fd = open(url.path, O_CREAT | O_EXCL | O_WRONLY, 0o644)
        guard fd >= 0 else { return false }
        close(fd)
        return true
    }
}

/// Runs the package's `theme` command with an argument list (never a shell
/// string), the way the menus and `theme set` do.
public enum ThemeCommand {
    public struct Outcome: Sendable, Equatable {
        public let status: Int32
        public let output: String

        public init(status: Int32, output: String) {
            self.status = status
            self.output = output
        }

        /// The last line printed, for a status line under a control.
        public var lastLine: String {
            output.split(whereSeparator: \.isNewline).last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        }
    }

    /// `theme set NAME` for a family as the Appearance setting asks:
    /// following macOS, a pair is named by its family (`theme set harbour`),
    /// which picks the variant for the current appearance; dark or light name
    /// that variant. Graphite and Daylight are two files of one pair.
    public static func setArguments(_ family: ThemeFamily, appearance: ThemeAppearance, systemIsDark: Bool) -> [String] {
        let wantsDark: Bool
        switch appearance {
        case .dark: wantsDark = true
        case .light: wantsDark = false
        case .system: wantsDark = systemIsDark
        }
        if family.id == ThemeFollow.systemFamily || !family.isFilePair || appearance != .system {
            return ["set", family.variant(dark: wantsDark)?.name ?? family.id]
        }
        return ["set", family.id]
    }

    public static func run(_ arguments: [String], location: ThemeLocation) async -> Outcome {
        let executable = location.themeCommand
        return await Task.detached(priority: .userInitiated) { () -> Outcome in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            do {
                try process.run()
            } catch {
                return Outcome(status: -1, output: "The theme command could not start: \(error.localizedDescription)")
            }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return Outcome(status: process.terminationStatus, output: String(decoding: data, as: UTF8.self))
        }.value
    }
}

/// What macOS shows now, read from the global AppleInterfaceStyle default
/// (the apps set their own appearance, so theirs says nothing about the system).
public enum SystemAppearance {
    public static func isDark() -> Bool {
        let any = kCFPreferencesAnyApplication
        CFPreferencesAppSynchronize(any)
        let style = CFPreferencesCopyAppValue("AppleInterfaceStyle" as CFString, any) as? String
        return style?.lowercased() == "dark"
    }

    /// Posted by macOS to every app when dark mode turns on or off.
    public static let changedNotification = Notification.Name("AppleInterfaceThemeChangedNotification")
}
