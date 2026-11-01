import AppKit
import SwiftUI
import EventKit
import IcebergKit

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
    /// `events(matching:)` is synchronous and can take a while with many
    /// calendars, so it runs here, one fetch at a time (FetchCoalescer).
    private let fetchQueue = DispatchQueue(label: "com.grandline.iceberg.today.fetch", qos: .userInitiated)
    private var fetches = FetchCoalescer()
    /// Change notices come in bursts while calendars sync: one fetch per burst.
    private var changeWork: DispatchWorkItem?
    private static let changeSettle: TimeInterval = 0.3

    init(context: WidgetContext) {
        store = context.events
        availabilityChanged = context.availabilityChanged
        access = context.events.access(for: .event)
        store.onChange { [weak self] in
            guard let self else { return }
            self.stale = true
            guard self.isOpen else { return }
            self.changeWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, self.isOpen else { return }
                    self.reload()
                }
            }
            self.changeWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.changeSettle, execute: work)
        }
    }

    func shutDown() {
        changeWork?.cancel()
        fetches.cancel()
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
            if let generation = fetches.request() { fetch(generation) }
        case .notAsked:
            Task {
                if await store.requestAccess(for: .event) { reload() } else { access = store.access(for: .event) }
            }
        case .denied:
            events = []
        }
    }

    /// Reads today's events on the fetch queue and shows them on the main thread.
    private func fetch(_ generation: Int) {
        let eventStore = store.store
        let day = Agenda.today(Date())
        fetchQueue.async { [weak self] in
            let predicate = eventStore.predicateForEvents(withStart: day.start, end: day.end, calendars: nil)
            let found = eventStore.events(matching: predicate).map { e in
                AgendaEvent(id: e.calendarItemIdentifier, title: e.title ?? "Untitled", start: e.startDate,
                            end: e.endDate, isAllDay: e.isAllDay, calendar: e.calendar?.title ?? "")
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.fetched(found, generation: generation) }
            }
        }
    }

    private func fetched(_ found: [AgendaEvent], generation: Int) {
        let (useResult, next) = fetches.finished(generation)
        if useResult {
            let upcoming = Agenda.upcoming(found, now: Date())
            if upcoming != events { events = upcoming }
        }
        if let next { fetch(next) }
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
