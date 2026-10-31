import AppKit
import SwiftUI
import EventKit
import DenDenKit

/// Open reminders due today or overdue. Ticking one completes it in
/// Reminders (and so on every device signed in to the same account).
@MainActor
final class RemindersWidget: ObservableObject, NotchWidget {
    let id = "reminders"
    let placement = WidgetPlacement.section

    @Published private(set) var reminders: [AgendaReminder] = []
    @Published private(set) var access: SharedEventStore.Access {
        didSet { if access != oldValue { availabilityChanged() } }
    }
    private let availabilityChanged: @MainActor () -> Void

    /// Hidden while access is turned down; Settings says how to allow it.
    var isAvailable: Bool { access != .denied }
    /// Ticked in this session, shown struck through until the panel closes.
    @Published private(set) var ticked: Set<String> = []
    private let store: SharedEventStore
    private var stale = true
    private var isOpen = false

    init(context: WidgetContext) {
        store = context.events
        availabilityChanged = context.availabilityChanged
        access = context.events.access(for: .reminder)
        store.onChange { [weak self] in
            guard let self else { return }
            self.stale = true
            if self.isOpen { self.reload() }
        }
    }

    func makeView() -> AnyView { AnyView(RemindersView(model: self)) }

    func panelWillOpen() {
        isOpen = true
        if stale || access != .granted { reload() }
    }

    func panelDidClose() {
        isOpen = false
        if !ticked.isEmpty {
            reminders.removeAll { ticked.contains($0.id) }
            ticked = []
        }
    }

    func reload() {
        access = store.access(for: .reminder)
        switch access {
        case .granted:
            stale = false
            let end = Agenda.today(Date()).end
            let predicate = store.store.predicateForIncompleteReminders(withDueDateStarting: nil, ending: end, calendars: nil)
            store.store.fetchReminders(matching: predicate) { found in
                let items: [AgendaReminder] = (found ?? []).map { r in
                    let parts = r.dueDateComponents
                    let date = parts.flatMap { Calendar.current.date(from: $0) }
                    let timed = parts?.hour != nil
                    return AgendaReminder(id: r.calendarItemIdentifier, title: r.title ?? "Untitled",
                                          due: timed ? date : nil, dueDay: timed ? nil : date,
                                          priority: r.priority, isCompleted: r.isCompleted)
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let keep = self.reminders.filter { self.ticked.contains($0.id) }
                    let fresh = Agenda.dueToday(items, now: Date()).filter { !self.ticked.contains($0.id) }
                    self.reminders = keep + fresh
                }
            }
        case .notAsked:
            Task {
                if await store.requestAccess(for: .reminder) { reload() } else { access = store.access(for: .reminder) }
            }
        case .denied:
            reminders = []
        }
    }

    /// Completes (or, ticked again before closing, reopens) a reminder.
    func toggle(_ item: AgendaReminder) {
        guard let reminder = store.store.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        let done = !ticked.contains(item.id)
        reminder.isCompleted = done
        do {
            try store.store.save(reminder, commit: true)
            if done { ticked.insert(item.id) } else { ticked.remove(item.id) }
        } catch {
            Log.info("Could not save reminder: \(error.localizedDescription)")
        }
    }

    func openReminders() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
        }
    }

    func openSettings() { store.openPrivacySettings(for: .reminder) }
}

struct RemindersView: View {
    @ObservedObject var model: RemindersWidget
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: model.openReminders) { SectionCaption(text: "Reminders") }
                .buttonStyle(.plain)
            switch model.access {
            case .denied:
                EmptyNote(text: "Allow Reminders in System Settings", action: model.openSettings)
            case .notAsked:
                EmptyNote(text: "Asking for Reminders access")
            case .granted:
                if model.reminders.isEmpty {
                    EmptyNote(text: "Nothing due today")
                } else {
                    ForEach(model.reminders) { item in
                        ReminderRow(item: item, done: model.ticked.contains(item.id)) { model.toggle(item) }
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct ReminderRow: View {
    @EnvironmentObject var theme: ThemeStore
    let item: AgendaReminder
    let done: Bool
    let toggle: @MainActor () -> Void

    var overdue: Bool {
        guard let d = item.due ?? item.dueDay else { return false }
        return d < Agenda.today(Date()).start
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Button(action: toggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(done ? theme.highlight : theme.muted)
            }
            .buttonStyle(.plain)
            .help(done ? "Mark as not done" : "Mark as done")
            Text(item.title)
                .font(.system(size: 13))
                .strikethrough(done, color: theme.muted)
                .foregroundStyle(done ? theme.muted : theme.foreground)
                .lineLimit(1)
            if overdue && !done {
                Text("overdue").font(.system(size: 11)).foregroundStyle(theme.muted)
            }
        }
    }
}
