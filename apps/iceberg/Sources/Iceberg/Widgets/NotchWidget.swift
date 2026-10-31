import SwiftUI
import IcebergKit

/// Where a built-in widget sits in the open panel.
enum WidgetPlacement {
    /// A column in the main row (Now Playing, Today, Reminders).
    case section
    /// A small item in the top band, beside the camera (Battery).
    case header
}

/// What every built-in widget gets when it is made.
@MainActor
struct WidgetContext {
    let theme: ThemeStore
    let events: SharedEventStore
    let settings: IcebergSettings
    /// Call when `isAvailable` changes (a permission granted or taken
    /// away), so the panel adds or drops the widget.
    let availabilityChanged: @MainActor () -> Void
}

/// A built-in widget: one small module in `Widgets/`, listed once in
/// `WidgetRegistry`. It owns its state, makes its own view, and hears when
/// the panel opens and closes so it can start and stop its work.
@MainActor
protocol NotchWidget: AnyObject {
    var id: String { get }
    var placement: WidgetPlacement { get }
    /// False hides the widget (Battery on a Mac without one, Today when
    /// Calendars access was turned down).
    var isAvailable: Bool { get }
    func makeView() -> AnyView
    /// The panel is about to open: refresh anything stale.
    func panelWillOpen()
    /// Every panel is closed: stop anything that only matters while open.
    func panelDidClose()
    /// Turned off in Settings: stop everything; the widget is let go.
    func shutDown()
}

extension NotchWidget {
    var isAvailable: Bool { true }
    func panelWillOpen() {}
    func panelDidClose() {}
    func shutDown() {}
}

/// The small caption above a section ("Today"), 11 pt and muted.
struct SectionCaption: View {
    @EnvironmentObject var theme: ThemeStore
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(theme.muted)
            .lineLimit(1)
    }
}

/// A one-line note in place of content ("Nothing due today").
struct EmptyNote: View {
    @EnvironmentObject var theme: ThemeStore
    let text: String
    var action: (@MainActor () -> Void)?
    var body: some View {
        if let action {
            Button(action: action) {
                Text(text).font(.system(size: 13)).foregroundStyle(theme.highlight).lineLimit(2)
            }
            .buttonStyle(.plain)
        } else {
            Text(text).font(.system(size: 13)).foregroundStyle(theme.muted).lineLimit(2)
        }
    }
}
