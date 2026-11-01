import IcebergKit

/// Every built-in widget, by the name used in `iceberg.toml` (`panel = [...]`).
/// To add one: write `Widgets/<Name>/<Name>Widget.swift` conforming to
/// `NotchWidget`, add a line here, and add it to `PanelCatalog.builtins` in
/// IcebergKit (its title and description for Settings).
@MainActor
enum WidgetRegistry {
    static let makers: [String: @MainActor (WidgetContext) -> NotchWidget] = [
        "now-playing": { NowPlayingWidget(context: $0) },
        "today": { TodayWidget(context: $0) },
        "reminders": { RemindersWidget(context: $0) },
        "battery": { _ in BatteryWidget() },
        "shelf": { ShelfWidget(context: $0) },
    ]
}
