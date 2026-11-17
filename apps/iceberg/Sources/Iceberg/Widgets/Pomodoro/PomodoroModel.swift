import AppKit
import Combine
import UserNotifications
import IcebergKit

/// The Pomodoro timer, one for the whole app: the panel on every display,
/// the closed notch, `iceberg pomodoro ...` and `iceberg://pomodoro/...`
/// all drive this one.
///
/// Nothing ticks. The timer keeps the phase's end date (IcebergKit's
/// `PomodoroTimer`), and one timer is set for that moment; the views work
/// out the time left from the clock, once a second and only while they are
/// on screen. A Mac asleep at the end catches up on wake (a timer does not
/// count time asleep), and the state is kept in `pomodoro.json`, so a
/// running timer carries on after Iceberg restarts.
@MainActor
final class PomodoroModel: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    @Published private(set) var timer: PomodoroTimer
    @Published private(set) var config: PomodoroConfig
    /// Notices are turned off for Iceberg in System Settings, Notifications.
    @Published private(set) var notificationsDenied = false

    /// A phase ran out (not skipped): the notch pulses.
    var onPhaseEnd: (@MainActor (PomodoroPhaseEnd) -> Void)?
    /// Writes a new focus length to iceberg.toml (`pomodoro_focus`).
    var saveFocus: (@MainActor (Int) -> Void)?

    private let file: URL
    private var endTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var configured = false
    private var notificationsReady = false
    /// The user journeys drive Iceberg on a test Mac: no permission prompt there.
    private let quiet = ProcessInfo.processInfo.environment["GRAND_LINE_JOURNEY"] == "1"

    init(paths: IcebergPaths) {
        file = paths.pomodoroFile
        let config = PomodoroConfig()
        self.config = config
        timer = PomodoroTimer.load(from: file, config: config)
        super.init()
        let workspace = NSWorkspace.shared.notificationCenter
        observers = [
            // A timer does not count time asleep: work it out again from the clock.
            workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.catchUp() }
            },
            NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.catchUp() }
            },
        ]
        // Phase ends missed while Iceberg was not running are worked out on
        // the first read of the settings (apply), which has auto-start.
        schedule()
    }

    deinit {
        for observer in observers {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: Settings and commands

    /// The `pomodoro_*` settings, on every good read of iceberg.toml. The
    /// first read after a start changes only a phase not yet begun.
    func apply(_ next: PomodoroConfig) {
        guard !configured || next != config else { return }
        let previous = configured ? config : nil
        configured = true
        config = next
        var t = timer
        t.apply(next, previous: previous, at: Date())
        commit(t)
        catchUp()
    }

    func perform(_ command: PomodoroCommand) {
        var t = timer
        let wasRunning = t.status == .running
        command.apply(to: &t, at: Date(), config: config)
        commit(t)
        if t.status == .running && !wasRunning { prepareNotifications() }
    }

    func toggle() { perform(.toggle) }
    func reset() { perform(.reset) }
    func skip() { perform(.skip) }

    /// A new focus length from the panel (a preset, or 5 more or fewer).
    func setFocus(_ minutes: Int) {
        let m = min(max(minutes, PomodoroConfig.focusRange.lowerBound), PomodoroConfig.focusRange.upperBound)
        guard m != config.focus else { return }
        saveFocus?(m)
    }

    // MARK: The end of a phase

    /// Moves past any phase end that has passed, announces the latest one
    /// (if recent), and sets the one timer for the next end.
    private func catchUp() {
        guard configured else { return }
        var t = timer
        let now = Date()
        let ends = t.update(at: now, config: config)
        commit(t)
        if let last = ends.last, last.shouldAnnounce(at: now) { announce(last) }
    }

    private func commit(_ next: PomodoroTimer) {
        if next != timer {
            timer = next
            do { try next.save(to: file) } catch { Log.info("pomodoro.json could not be written: \(error.localizedDescription)") }
        }
        schedule()
    }

    /// One timer, at the phase's end; none while nothing runs.
    private func schedule() {
        endTimer?.invalidate()
        endTimer = nil
        guard timer.status == .running, let end = timer.endsAt else { return }
        let t = Timer(fire: end, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.catchUp() }
        }
        t.tolerance = 0.2
        RunLoop.main.add(t, forMode: .common)
        endTimer = t
    }

    private func announce(_ end: PomodoroPhaseEnd) {
        onPhaseEnd?(end)
        guard !quiet, Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = end.title
        content.body = end.body
        content.threadIdentifier = "pomodoro"
        if config.sound { content.sound = .default }
        // One notice at a time: a new one replaces the last.
        let request = UNNotificationRequest(identifier: "pomodoro", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { Log.info("The Pomodoro notice could not be shown: \(error.localizedDescription)") }
        }
    }

    // MARK: Notices

    /// The first time a timer starts, macOS asks whether Iceberg may show
    /// notices (never at launch). Do Not Disturb and Focus hold them as
    /// they hold every app's.
    private func prepareNotifications() {
        guard !quiet, Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        if !notificationsReady {
            center.delegate = self
            notificationsReady = true
        }
        center.requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.refreshNotificationStatus() } }
        }
    }

    /// Whether notices are turned off, for Settings.
    func refreshNotificationStatus() {
        guard !quiet, Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            let denied = settings.authorizationStatus == .denied
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self, self.notificationsDenied != denied else { return }
                    self.notificationsDenied = denied
                }
            }
        }
    }

    func openNotificationSettings() {
        let id = Bundle.main.bundleIdentifier ?? "com.grandline.iceberg"
        if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=\(id)") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Iceberg is an agent app, often counted as in front: show the notice anyway.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }
}
