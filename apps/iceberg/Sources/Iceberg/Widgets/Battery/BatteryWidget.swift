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
    private var source: CFRunLoopSource?
    private var stale = true
    private var isOpen = false

    var isAvailable: Bool { reading != nil }

    init() {
        reading = Self.read()
        stale = false
        // The widget lives as long as the app (PanelHost keeps it), so an
        // unretained pointer is safe.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource(powerSourceChanged, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
            source = src
        }
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
/// callback cannot carry the main actor.
private func powerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    guard let context else { return }
    let widget = Unmanaged<BatteryWidget>.fromOpaque(context).takeUnretainedValue()
    MainActor.assumeIsolated { widget.powerChanged() }
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
