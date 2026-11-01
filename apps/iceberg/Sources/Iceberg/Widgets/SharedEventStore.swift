import EventKit
import AppKit
import IcebergKit

/// One EventKit store for Today and Reminders. Google calendars show up here
/// once they are added in System Settings, Internet Accounts, because macOS
/// Calendar syncs them into EventKit.
///
/// It listens for EventKit's change notice (no polling). While every panel
/// is closed a change only marks the data stale; it is fetched on next open.
@MainActor
final class SharedEventStore {
    let store = EKEventStore()
    private var listeners: [@MainActor () -> Void] = []
    private var asked: Set<UInt> = []
    /// One permission prompt at a time, with a pause between two.
    private var pacing = PromptPacing()

    init() {
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.listeners.forEach { $0() } }
        }
        // The day changed (midnight, or waking on a new day).
        NotificationCenter.default.addObserver(forName: .NSCalendarDayChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.listeners.forEach { $0() } }
        }
    }

    func onChange(_ listener: @escaping @MainActor () -> Void) { listeners.append(listener) }

    enum Access { case granted, denied, notAsked }

    func access(for type: EKEntityType) -> Access {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess: return .granted
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    /// Asks once per launch; macOS itself only ever shows the prompt once.
    func requestAccess(for type: EKEntityType) async -> Bool {
        if access(for: type) == .granted { return true }
        guard !asked.contains(type.rawValue) else { return false }
        // Another widget is asking, or just did: this one asks on a later open.
        guard pacing.mayAsk(at: Date()) else { return false }
        asked.insert(type.rawValue)
        defer { pacing.answered(at: Date()) }
        do {
            switch type {
            case .event: return try await store.requestFullAccessToEvents()
            case .reminder: return try await store.requestFullAccessToReminders()
            @unknown default: return false
            }
        } catch {
            Log.info("EventKit access failed: \(error.localizedDescription)")
            return false
        }
    }

    /// Opens the Privacy pane for Calendars or Reminders.
    func openPrivacySettings(for type: EKEntityType) {
        let anchor = type == .event ? "Privacy_Calendars" : "Privacy_Reminders"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}
