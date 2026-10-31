import DenDenKit

/// Every built-in widget, by the name used in `denden.toml` (`builtin = [...]`).
/// To add one: write `Widgets/<Name>/<Name>Widget.swift` conforming to
/// `NotchWidget`, add a line here, and add its name to
/// `DenDenSettings.builtinWidgets` in DenDenKit.
@MainActor
enum WidgetRegistry {
    static let makers: [String: @MainActor (WidgetContext) -> NotchWidget] = [
        "now-playing": { NowPlayingWidget(context: $0) },
        "today": { TodayWidget(context: $0) },
        "reminders": { RemindersWidget(context: $0) },
        "battery": { _ in BatteryWidget() },
    ]
}
