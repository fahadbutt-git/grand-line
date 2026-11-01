import SwiftUI
import IOKit.ps
import IcebergKit

/// Battery level in the top band. macOS calls back when the power source
/// changes (IOPSNotificationCreateRunLoopSource), so there is no polling;
/// while the panel is closed a change is only noted.
@MainActor
final class BatteryWidget: ObservableObject, NotchWidget {
    let id = "battery"
    let placement = WidgetPlacement.header

    @Published private(set) var reading: BatteryReading?
    private var subscription: RunLoopSubscription?
    private var stale = true
    private var isOpen = false

    var isAvailable: Bool { reading != nil }

    init() {
        reading = Self.read()
        stale = false
        // The run-loop source points at the subscription, not at the widget.
        // The subscription removes the source before it is freed (shutDown, or
        // the widget let go), so the callback never reaches freed memory.
        subscription = RunLoopSubscription(make: { context in
            IOPSNotificationCreateRunLoopSource(powerSourceChanged, context)?.takeRetainedValue()
        }, onFire: { [weak self] in
            MainActor.assumeIsolated { self?.powerChanged() }
        })
    }

    /// Turned off in Settings: the power-source callback is removed now.
    func shutDown() {
        subscription?.cancel()
        subscription = nil
    }

    func makeView() -> AnyView { AnyView(BatteryView(model: self)) }

    func panelWillOpen() {
        isOpen = true
        if stale { refresh() }
    }

    func panelDidClose() { isOpen = false }

    fileprivate func powerChanged() {
        if isOpen { refresh() } else { stale = true }
    }

    private func refresh() {
        stale = false
        let now = Self.read()
        if now != reading { reading = now }
    }

    static func read() -> BatteryReading? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            if let d = IOPSGetPowerSourceDescription(info, ps)?.takeUnretainedValue() as? [String: Any],
               let reading = BatteryReading.parse(d) {
                return reading
            }
        }
        return nil
    }
}

/// IOKit's callback, on the main run loop. A plain function, because a C
/// callback cannot carry context of its own.
private func powerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    RunLoopSubscription.fire(context: context)
}

struct BatteryView: View {
    @ObservedObject var model: BatteryWidget
    @EnvironmentObject var theme: ThemeStore

    var body: some View {
        if let r = model.reading {
            HStack(spacing: 5) {
                Text("\(r.percent)%")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(r.isLow ? theme.color(.theme(.red)) ?? theme.foreground : theme.foreground)
                Image(systemName: r.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(r.isLow ? theme.color(.theme(.red)) ?? theme.foreground : theme.muted)
            }
            .help(r.summary)
        }
    }
}
