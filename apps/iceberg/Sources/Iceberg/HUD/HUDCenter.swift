import AppKit
import ApplicationServices
import CoreBluetooth
import IcebergKit
import SwiftUI

/// The HUDs in the notch (`hud_volume`, `hud_brightness`, `hud_battery`,
/// `hud_bluetooth`, `hud_replace_system`). It starts only the sources the
/// settings turn on, and stops the rest; each is pushed by macOS. A HUD
/// goes to `onEvent`, which shows it in the notch.
@MainActor
final class HUDCenter: ObservableObject {
    var onEvent: ((HUDEvent) -> Void)?

    /// Accessibility, which the brightness HUD and taking the keys need.
    @Published private(set) var accessibilityAllowed = AXIsProcessTrusted()
    /// The key tap is running.
    @Published private(set) var keysActive = false

    private var settings = IcebergSettings()
    private let volume = VolumeWatcher()
    private let battery = BatteryHUDWatcher()
    private let bluetooth = BluetoothWatcher()
    private let keys = MediaKeyTap()
    private var brightnessWork: DispatchWorkItem?
    private var accessibilityObserver: DistributedObserver?

    init() {
        volume.onChange = { [weak self] r in self?.emit(.volume(level: r.level, muted: r.muted)) }
        battery.onEvent = { [weak self] e in self?.emit(e) }
        bluetooth.onEvent = { [weak self] e in self?.emit(e) }
        keys.handler = { [weak self] key, down, isRepeat, flags in
            self?.mediaKey(key, down: down, isRepeat: isRepeat, flags: flags) ?? false
        }
    }

    /// The key tap is wanted: the brightness HUD, or taking the volume keys.
    private var wantsKeys: Bool {
        settings.hudBrightness || (settings.hudReplaceSystem && settings.hudVolume)
    }

    func apply(_ new: IcebergSettings) {
        settings = new
        new.hudVolume ? volume.start() : volume.stop()
        new.hudBattery ? battery.start() : battery.stop()
        new.hudBluetooth ? bluetooth.start() : bluetooth.stop()
        syncKeys()
        // Accessibility granted or taken away in System Settings: try the tap again.
        if wantsKeys, accessibilityObserver == nil {
            accessibilityObserver = DistributedObserver("com.apple.accessibility.api") { [weak self] _ in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    MainActor.assumeIsolated { self?.refreshPermissions() }
                }
            }
        } else if !wantsKeys {
            accessibilityObserver = nil
        }
    }

    private func syncKeys() {
        if wantsKeys {
            if !keys.isRunning, AXIsProcessTrusted() { keys.start() }
        } else {
            keys.stop()
        }
        if keysActive != keys.isRunning { keysActive = keys.isRunning }
    }

    /// The Settings window came forward, or Accessibility changed.
    func refreshPermissions() {
        let allowed = AXIsProcessTrusted()
        if allowed != accessibilityAllowed { accessibilityAllowed = allowed }
        if !allowed { keys.stop() }
        syncKeys()
    }

    /// Asks macOS to list Iceberg under Accessibility (its own prompt, once).
    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// Bluetooth access as macOS has it now.
    var bluetoothDenied: Bool {
        let state = CBManager.authorization
        return state == .denied || state == .restricted
    }

    func openPrivacySettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func emit(_ event: HUDEvent) {
        onEvent?(event)
    }

    // MARK: Keys

    /// True takes the key from macOS.
    private func mediaKey(_ key: MediaKey, down: Bool, isRepeat: Bool, flags: NSEvent.ModifierFlags) -> Bool {
        let fine = flags.contains(.option) && flags.contains(.shift)
        if key.isVolume {
            guard settings.hudVolume, settings.hudReplaceSystem else { return false }
            // Key-up goes with its key-down: taken when the device takes the change.
            guard down else { return VolumeWatcher.canSet(VolumeWatcher.defaultDevice()) }
            if key == .mute && isRepeat { return true }
            return volume.handle(key, fine: fine)
        }
        if key.isBrightness, settings.hudBrightness {
            if settings.hudReplaceSystem, let now = DisplayBrightness.get() {
                if down {
                    let next = LevelStep.next(now, up: key == .brightnessUp, fine: fine)
                    if DisplayBrightness.set(next) { emit(.brightness(level: next)) }
                }
                return true
            }
            // macOS changes it; read it back a moment later.
            if down {
                brightnessWork?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    MainActor.assumeIsolated {
                        if let level = DisplayBrightness.get() { self?.emit(.brightness(level: level)) }
                    }
                }
                brightnessWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
            }
        }
        return false
    }
}

/// A HUD in the closed notch: the symbol in the left wing, the level bar
/// and its text (or the text alone) in the right one. White on the black
/// notch, which it is part of, so it takes no material; the bar and the
/// symbol's state colours come from the theme. A new level slides the bar
/// and rolls the digits in place, and a new symbol (muted, charging)
/// replaces the old one, all critically damped.
struct HUDView: View {
    let event: HUDEvent
    /// The closed notch's height.
    let height: CGFloat
    /// The flare at each top corner, which nothing is drawn in.
    let inset: CGFloat
    @EnvironmentObject var theme: ThemeStore
    @ObservedObject private var display = DisplayOptions.shared

    var body: some View {
        let wing = NotchGeometry.hudWingWidth(collapsedHeight: height)
        let pad = NotchGeometry.wingPadding(collapsedHeight: height) + 4
        let change = Motion.content(reduceMotion: display.reduceMotion)
        HStack(spacing: 0) {
            // Sized to the notch, not to text: the hardware sets the scale.
            Image(systemName: event.symbol)
                .font(.system(size: (height * 0.42).rounded(), weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(symbolColor)
                .contentTransition(.symbolEffect(.replace))
                .animation(change, value: event.symbol)
                .padding(.leading, pad)
                .frame(width: wing, height: height, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                if let level = event.level {
                    LevelBar(level: level, color: theme.theme.accent.color, trackOpacity: display.increaseContrast ? 0.36 : 0.2)
                        .frame(height: 4)
                        .animation(change, value: level)
                }
                Text(event.text)
                    .font(TypeScale.numeral.weight(.medium))
                    .foregroundStyle(Color.white.opacity(display.increaseContrast ? 1 : 0.9))
                    .contentTransition(.numericText(value: event.level ?? 0))
                    .animation(change, value: event.text)
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.trailing, pad)
            .frame(width: wing, height: height, alignment: .trailing)
        }
        .padding(.horizontal, inset)
        .frame(height: height)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(event.label)
        .help(event.label)
    }

    private var symbolColor: Color {
        switch event.tone {
        case .normal: return Color.white
        case .good: return theme.color(.theme(.green)) ?? Color.white
        case .warning: return theme.color(.theme(.yellow)) ?? Color.white
        case .critical: return theme.color(.theme(.red)) ?? Color.white
        }
    }
}

/// A thin level bar: a faint track and the level in `color`, its end on
/// whole device pixels.
struct LevelBar: View {
    let level: Double
    let color: Color
    var trackOpacity: Double = 0.2
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { g in
            let filled = PixelGrid.align(max(0, min(1, level)) * g.size.width, scale: displayScale)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(trackOpacity))
                Capsule().fill(color).frame(width: filled)
            }
        }
    }
}
