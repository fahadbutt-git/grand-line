import AppKit
import SwiftUI
import EventKit
import DenDenKit

/// Today's calendar: all-day events, then what is left of the day. Reads
/// EventKit, so it shows every calendar macOS Calendar has, Google included.
@MainActor
final class TodayWidget: ObservableObject, NotchWidget {
    let id = "today"
    let placement = WidgetPlacement.section

    @Published private(set) var events: [AgendaEvent] = []
    @Published private(set) var access: SharedEventStore.Access {
        didSet { if access != oldValue { availabilityChanged() } }
    }
    private let availabilityChanged: @MainActor () -> Void

    /// Hidden while access is turned down; Settings says how to allow it.
    var isAvailable: Bool { access != .denied }
    private let store: SharedEventStore
    private var stale = true
    private var isOpen = false

    init(context: WidgetContext) {
        store = context.events
        availabilityChanged = context.availabilityChanged
        access = context.events.access(for: .event)
        store.onChange { [weak self] in
            guard let self else { return }
            self.stale = true
            if self.isOpen { self.reload() }
        }
    }

    func makeView() -> AnyView { AnyView(TodayView(model: self)) }

    func panelWillOpen() {
        isOpen = true
        // Past events drop off as the day goes on, so filter again each open.
        // Without access, look again: it may have been allowed since.
        if stale || access != .granted { reload() } else { events = Agenda.upcoming(events, now: Date()) }
    }

    func panelDidClose() { isOpen = false }

    func reload() {
        access = store.access(for: .event)
        switch access {
        case .granted:
            stale = false
            let day = Agenda.today(Date())
            let predicate = store.store.predicateForEvents(withStart: day.start, end: day.end, calendars: nil)
            let found = store.store.events(matching: predicate).map { e in
                AgendaEvent(id: e.calendarItemIdentifier, title: e.title ?? "Untitled", start: e.startDate,
                            end: e.endDate, isAllDay: e.isAllDay, calendar: e.calendar?.title ?? "")
            }
            events = Agenda.upcoming(found, now: Date())
        case .notAsked:
            Task {
                if await store.requestAccess(for: .event) { reload() } else { access = store.access(for: .event) }
            }
        case .denied:
            events = []
        }
    }

    func openCalendar() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    func openSettings() { store.openPrivacySettings(for: .event) }
}

struct TodayView: View {
    @ObservedObject var model: TodayWidget
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: model.openCalendar) { SectionCaption(text: "Today") }
                .buttonStyle(.plain)
            switch model.access {
            case .denied:
                EmptyNote(text: "Allow Calendars in System Settings", action: model.openSettings)
            case .notAsked:
                EmptyNote(text: "Asking for Calendars access")
            case .granted:
                if model.events.isEmpty {
                    EmptyNote(text: "Nothing more today")
                } else {
                    ForEach(model.events) { event in
                        EventRow(event: event, isCurrent: Agenda.isCurrent(event, now: Date()))
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct EventRow: View {
    @EnvironmentObject var theme: ThemeStore
    let event: AgendaEvent
    let isCurrent: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(Agenda.timeLabel(event))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(isCurrent ? theme.highlight : theme.muted)
                .frame(width: 46, alignment: .leading)
            Text(event.title)
                .font(.system(size: 13))
                .foregroundStyle(theme.foreground)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .help(event.calendar)
    }
}
