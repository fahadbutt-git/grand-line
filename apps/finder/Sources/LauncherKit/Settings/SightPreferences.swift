import Foundation

/// Everything Sight's Settings window changes, kept in Sight's defaults
/// domain (com.grandline.sight). The launcher shortcut is LaunchKit's
/// `HotkeySetting`; the rest is here.
public struct SightPreferences: Sendable, Equatable {
    public static let menuBarIconKey = "ShowMenuBarIcon"
    public static let launchAtLoginKey = "LaunchAtLogin"
    public static let resultLimitsKey = "ResultLimits"

    public var showMenuBarIcon = true
    public var launchAtLogin = true
    /// Hide the window after a setting is changed from it.
    public var closeAfterSettingChange = false
    public var sources = SourceSettings.standard
    /// Rows per section, where changed.
    public var limits: [ResultSection: Int] = [:]
    public var engines = WebEngineList.standard
    public var assistantFallbacks = true
    public var driveFallback = true

    public init() {}

    public init(defaults: UserDefaults) {
        showMenuBarIcon = defaults.object(forKey: Self.menuBarIconKey) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Self.launchAtLoginKey) as? Bool ?? true
        closeAfterSettingChange = defaults.bool(forKey: SettingsActionsProvider.closeAfterChangeKey)
        sources = SourceSettings(order: defaults.stringArray(forKey: SourceSettings.orderKey),
                                 disabled: defaults.stringArray(forKey: SourceSettings.disabledKey))
        limits = Self.limits(from: defaults.dictionary(forKey: Self.resultLimitsKey))
        engines = WebEngineList.parse(defaults.object(forKey: WebEngineList.defaultsKey))
        assistantFallbacks = defaults.object(forKey: WebEngineList.assistantsKey) as? Bool ?? true
        driveFallback = defaults.object(forKey: WebEngineList.driveKey) as? Bool ?? true
    }

    /// Writes every key; a value equal to its default is written too, so the
    /// file says what the window shows.
    public func save(to defaults: UserDefaults) {
        defaults.set(showMenuBarIcon, forKey: Self.menuBarIconKey)
        defaults.set(launchAtLogin, forKey: Self.launchAtLoginKey)
        defaults.set(closeAfterSettingChange, forKey: SettingsActionsProvider.closeAfterChangeKey)
        defaults.set(sources.storedOrder, forKey: SourceSettings.orderKey)
        defaults.set(sources.storedDisabled, forKey: SourceSettings.disabledKey)
        defaults.set(Self.stored(limits), forKey: Self.resultLimitsKey)
        defaults.set(WebEngineList.stored(engines), forKey: WebEngineList.defaultsKey)
        defaults.set(assistantFallbacks, forKey: WebEngineList.assistantsKey)
        defaults.set(driveFallback, forKey: WebEngineList.driveKey)
    }

    /// Section names ("files") to counts, clamped to `ResultLayout.limitRange`.
    public static func limits(from stored: [String: Any]?) -> [ResultSection: Int] {
        var out: [ResultSection: Int] = [:]
        for (key, value) in stored ?? [:] {
            guard let section = ResultSection.named(key), section != .topHit,
                  let count = (value as? NSNumber)?.intValue ?? (value as? Int) else { continue }
            out[section] = min(max(count, ResultLayout.limitRange.lowerBound), ResultLayout.limitRange.upperBound)
        }
        return out
    }

    public static func stored(_ limits: [ResultSection: Int]) -> [String: Int] {
        var out: [String: Int] = [:]
        for (section, count) in limits where count != section.limit { out[section.name] = count }
        return out
    }

    /// The result layout these settings give.
    public var layout: ResultLayout {
        ResultLayout(order: sources.sectionOrder, limits: limits)
    }

    public var fallbacks: WebEngineList.Fallbacks {
        WebEngineList.Fallbacks(engines: engines.filter(\.fallback), assistants: assistantFallbacks, drive: driveFallback)
    }
}

public extension ResultSection {
    /// A stable name for settings files.
    var name: String {
        switch self {
        case .favourites: return "favourites"
        case .recents: return "recents"
        case .topHit: return "topHit"
        case .answers: return "answers"
        case .apps: return "apps"
        case .grandLine: return "grandLine"
        case .windows: return "windows"
        case .system: return "system"
        case .bookmarks: return "bookmarks"
        case .snippets: return "snippets"
        case .symbols: return "symbols"
        case .files: return "files"
        case .web: return "web"
        case .otherActions: return "otherActions"
        }
    }

    static func named(_ name: String) -> ResultSection? {
        allCases.first { $0.name == name }
    }
}
