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
    /// The shelf's files, shared by every panel and the drop basket.
    let shelf: ShelfModel
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

/// The small caption above a section ("Today"): 11 pt medium, muted.
struct SectionCaption: View {
    @EnvironmentObject var theme: ThemeStore
    let text: String
    /// A count beside the caption (the shelf's files), in tabular digits.
    var count: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(text)
                .font(TypeScale.captionEmphasis)
                .foregroundStyle(theme.muted)
                .lineLimit(1)
            if let count {
                Text("\(count)")
                    .font(TypeScale.numeral)
                    .foregroundStyle(theme.muted.opacity(0.75))
                    .contentTransition(.numericText(value: Double(count)))
            }
        }
    }
}

/// A section caption that opens its app ("Today" opens Calendar): a
/// chevron comes in beside it while the pointer rests on it, and it dims
/// on mouse-down.
struct CaptionLink: View {
    @EnvironmentObject var theme: ThemeStore
    let text: String
    let help: String
    let action: @MainActor () -> Void
    @Local private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 3) {
                SectionCaption(text: text)
                Image(systemName: "chevron.right")
                    .font(TypeScale.label.weight(.semibold))
                    .foregroundStyle(theme.muted)
                    .opacity(hovering ? 1 : 0)
                    .offset(x: hovering ? 0 : -3)
            }
        }
        .buttonStyle(PanelButtonStyle(kind: .text))
        .onHover { inside in withAnimation(Motion.hover) { hovering = inside } }
        .help(help)
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
                Text(text).font(TypeScale.body).foregroundStyle(theme.highlight).lineLimit(2)
            }
            .buttonStyle(PanelButtonStyle(kind: .text))
        } else {
            Text(text).font(TypeScale.body).foregroundStyle(theme.muted).lineLimit(2)
        }
    }
}
