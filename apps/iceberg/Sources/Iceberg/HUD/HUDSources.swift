import AppKit
import CoreAudio
import IOBluetooth
import IOKit.ps
import IcebergKit

// The sources of HUD events. Each is pushed by macOS (a CoreAudio property
// listener, IOKit's power-source notice, IOBluetooth's connect notice, a
// keyboard event tap) and runs only while its HUD is turned on. None polls.

// MARK: Volume

/// The default output device's volume and mute, from CoreAudio property
/// listeners (and a listener for the default device changing). No permission.
@MainActor
final class VolumeWatcher {
    /// A change worth a HUD (`VolumeHUDPolicy`).
    var onChange: ((VolumeHUDPolicy.Reading) -> Void)?

    private var device = AudioObjectID(kAudioObjectUnknown)
    private var last: VolumeHUDPolicy.Reading?
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var deviceListeners: [(AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private(set) var isRunning = false

    /// `kAudioHardwareServiceDeviceProperty_VirtualMainVolume` ('vmvc'): the
    /// one volume the keys and Control Centre set, whatever the channels.
    static let virtualMainVolume = AudioObjectPropertySelector(0x766D_7663)

    func start() {
        guard !isRunning else { return }
        isRunning = true
        var address = Self.defaultDeviceAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.attach(Self.defaultDevice()) } }
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block) == noErr {
            systemListener = block
        }
        attach(Self.defaultDevice())
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        if let block = systemListener {
            var address = Self.defaultDeviceAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, DispatchQueue.main, block)
        }
        systemListener = nil
        detach()
        last = nil
    }

    private func attach(_ id: AudioObjectID) {
        guard isRunning else { return }
        if id == device, !deviceListeners.isEmpty { return }
        detach()
        device = id
        guard id != AudioObjectID(kAudioObjectUnknown) else { return }
        // The first reading of a device is not news.
        last = Self.read(id)
        // The virtual main volume where the device has it, else the main or
        // per-channel volume (built-in speakers often have only channels 1 and 2).
        let watched: [(AudioObjectPropertySelector, AudioObjectPropertyElement)] = [
            (Self.virtualMainVolume, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
            (kAudioDevicePropertyVolumeScalar, 1),
            (kAudioDevicePropertyVolumeScalar, 2),
            (kAudioDevicePropertyMute, kAudioObjectPropertyElementMain),
        ]
        for (selector, element) in watched {
            var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput,
                                                     mElement: element)
            guard AudioObjectHasProperty(id, &address) else { continue }
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                MainActor.assumeIsolated { self?.changed() }
            }
            if AudioObjectAddPropertyListenerBlock(id, &address, DispatchQueue.main, block) == noErr {
                deviceListeners.append((address, block))
            }
        }
    }

    private func detach() {
        for (address, block) in deviceListeners {
            var a = address
            AudioObjectRemovePropertyListenerBlock(device, &a, DispatchQueue.main, block)
        }
        deviceListeners = []
        device = AudioObjectID(kAudioObjectUnknown)
    }

    private func changed() {
        guard let now = Self.read(device) else { return }
        let previous = last
        last = now
        if VolumeHUDPolicy.shows(previous: previous, current: now) { onChange?(now) }
    }

    // MARK: Reading and setting

    static var defaultDeviceAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                   mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }

    static func defaultDevice() -> AudioObjectID {
        var address = defaultDeviceAddress
        var id = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr ? id : AudioObjectID(kAudioObjectUnknown)
    }

    private static func address(_ selector: AudioObjectPropertySelector, element: UInt32 = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
    }

    static func level(_ id: AudioObjectID) -> Double? {
        for (selector, element) in [(virtualMainVolume, kAudioObjectPropertyElementMain),
                                    (kAudioDevicePropertyVolumeScalar, kAudioObjectPropertyElementMain),
                                    (kAudioDevicePropertyVolumeScalar, UInt32(1))] {
            var a = address(selector, element: element)
            guard AudioObjectHasProperty(id, &a) else { continue }
            var value = Float32(0)
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr { return Double(value) }
        }
        return nil
    }

    static func muted(_ id: AudioObjectID) -> Bool {
        var a = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(id, &a) else { return false }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value) == noErr && value != 0
    }

    static func read(_ id: AudioObjectID) -> VolumeHUDPolicy.Reading? {
        guard id != AudioObjectID(kAudioObjectUnknown), let level = level(id) else { return nil }
        return VolumeHUDPolicy.Reading(level: level, muted: muted(id))
    }

    /// Whether Iceberg can set this device's volume (HDMI outputs often cannot).
    static func canSet(_ id: AudioObjectID) -> Bool {
        var a = address(virtualMainVolume)
        guard AudioObjectHasProperty(id, &a) else { return false }
        var settable = DarwinBoolean(false)
        return AudioObjectIsPropertySettable(id, &a, &settable) == noErr && settable.boolValue
    }

    static func setLevel(_ id: AudioObjectID, _ level: Double) {
        var a = address(virtualMainVolume)
        var value = Float32(min(max(level, 0), 1))
        AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<Float32>.size), &value)
    }

    static func setMuted(_ id: AudioObjectID, _ on: Bool) {
        var a = address(kAudioDevicePropertyMute)
        var settable = DarwinBoolean(false)
        guard AudioObjectHasProperty(id, &a), AudioObjectIsPropertySettable(id, &a, &settable) == noErr,
              settable.boolValue else { return }
        var value = UInt32(on ? 1 : 0)
        AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
    }

    /// A volume key Iceberg took (`hud_replace_system`): the same steps
    /// macOS takes, and Volume Up unmutes. The listeners then show the HUD.
    /// False when this output's volume cannot be set, so the key goes on to macOS.
    func handle(_ key: MediaKey, fine: Bool) -> Bool {
        let id = Self.defaultDevice()
        guard Self.canSet(id), let now = Self.read(id) else { return false }
        switch key {
        case .mute:
            Self.setMuted(id, !now.muted)
        case .soundUp:
            if now.muted { Self.setMuted(id, false) }
            Self.setLevel(id, LevelStep.next(now.level, up: true, fine: fine))
        case .soundDown:
            let next = LevelStep.next(now.level, up: false, fine: fine)
            Self.setLevel(id, next)
            if next <= 0 { Self.setMuted(id, true) }
        default:
            return false
        }
        return true
    }
}

// MARK: Brightness

/// The built-in display's brightness, through Apple's DisplayServices
/// (loaded by name; when it is not there, brightness HUDs are simply not shown).
enum DisplayBrightness {
    private typealias GetFunction = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFunction = @convention(c) (UInt32, Float) -> Int32

    nonisolated(unsafe) private static let library = dlopen(
        "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)

    private static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let library, let raw = dlsym(library, name) else { return nil }
        return unsafeBitCast(raw, to: T.self)
    }

    /// The built-in display, else the main one.
    static func display() -> CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        if CGGetOnlineDisplayList(16, &ids, &count) == .success {
            for id in ids.prefix(Int(count)) where CGDisplayIsBuiltin(id) != 0 { return id }
        }
        return CGMainDisplayID()
    }

    static func get() -> Double? {
        guard let get = symbol("DisplayServicesGetBrightness", as: GetFunction.self) else { return nil }
        var value: Float = 0
        return get(display(), &value) == 0 ? Double(value) : nil
    }

    static func set(_ level: Double) -> Bool {
        guard let set = symbol("DisplayServicesSetBrightness", as: SetFunction.self) else { return false }
        return set(display(), Float(min(max(level, 0), 1))) == 0
    }
}

// MARK: Media keys

/// The volume, mute and brightness keys, from a keyboard event tap. It
/// needs Accessibility (System Settings, Privacy & Security). Iceberg hears
/// only those keys (system-defined events), and only while a HUD that needs
/// them is on. `handler` returns true to take a key, so macOS does not
/// act on it (and shows no HUD of its own).
@MainActor
final class MediaKeyTap {
    var handler: ((MediaKey, _ down: Bool, _ isRepeat: Bool, NSEvent.ModifierFlags) -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    /// False when macOS refuses the tap (Accessibility not allowed).
    @discardableResult
    func start() -> Bool {
        if tap != nil { return true }
        let mask = CGEventMask(1) << 14 // NX_SYSDEFINED
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: mask, callback: mediaKeyTapCallback,
                                           userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        let src = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        tap = port
        source = src
        return true
    }

    func stop() {
        guard let port = tap else { return }
        CGEvent.tapEnable(tap: port, enable: false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        CFMachPortInvalidate(port)
        tap = nil
        source = nil
    }

    /// True to swallow the event.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        guard type.rawValue == 14, let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, ns.subtype.rawValue == 8,
              let key = MediaKey.decode(data1: ns.data1) else { return false }
        return handler?(key.key, key.down, key.isRepeat, ns.modifierFlags) ?? false
    }
}

/// The event tap's C callback, on the main run loop.
private func mediaKeyTapCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                                 refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(refcon).takeUnretainedValue()
    let swallow = MainActor.assumeIsolated { tap.handle(type: type, event: event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}

// MARK: Battery

/// The power source changing (IOKit's notice), for the battery HUD: power
/// connected or removed, and the level falling to 20% and 10%.
@MainActor
final class BatteryHUDWatcher {
    var onEvent: ((HUDEvent) -> Void)?
    private var subscription: RunLoopSubscription?
    private var last: BatteryReading?

    var isRunning: Bool { subscription != nil }

    func start() {
        guard subscription == nil else { return }
        last = BatteryWidget.read()
        subscription = RunLoopSubscription(make: { context in
            IOPSNotificationCreateRunLoopSource(hudPowerSourceChanged, context)?.takeRetainedValue()
        }, onFire: { [weak self] in
            MainActor.assumeIsolated { self?.changed() }
        })
    }

    func stop() {
        subscription?.cancel()
        subscription = nil
        last = nil
    }

    private func changed() {
        guard let now = BatteryWidget.read() else { return }
        let previous = last
        last = now
        if let reason = BatteryHUDPolicy.reason(previous: previous, current: now) {
            onEvent?(.battery(now, reason: reason))
        }
    }
}

private func hudPowerSourceChanged(_ context: UnsafeMutableRawPointer?) {
    RunLoopSubscription.fire(context: context)
}

// MARK: Bluetooth headphones

/// Headphones connecting (IOBluetooth's connect notice), with their
/// battery when macOS knows it (AirPods report each bud and the case). The
/// first use asks for Bluetooth access. Connections already there when it
/// starts are not shown.
@MainActor
final class BluetoothWatcher: NSObject {
    var onEvent: ((HUDEvent) -> Void)?
    private var notification: IOBluetoothUserNotification?
    private var since = Date()
    private var pending: [DispatchWorkItem] = []

    var isRunning: Bool { notification != nil }

    func start() {
        guard notification == nil else { return }
        since = Date()
        notification = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
    }

    func stop() {
        notification?.unregister()
        notification = nil
        pending.forEach { $0.cancel() }
        pending = []
    }

    @objc private func connected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        guard DeviceSymbol.announces(connectedAt: Date(), listeningSince: since), Self.isHeadphones(device) else { return }
        // The battery levels arrive a moment after the link comes up: one look, a little later.
        let work = DispatchWorkItem { [weak self, weak device] in
            MainActor.assumeIsolated {
                guard let self, let device, device.isConnected() else { return }
                self.onEvent?(.device(name: device.name ?? "Headphones", battery: Self.battery(device)))
            }
        }
        pending = pending.filter { !$0.isCancelled }
        pending.append(work)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
    }

    static func isHeadphones(_ device: IOBluetoothDevice) -> Bool {
        // Major device class 4 is audio and video.
        if UInt32(device.deviceClassMajor) == 0x04 { return true }
        let name = (device.name ?? "").lowercased()
        return name.contains("airpods") || name.contains("beats")
    }

    static func battery(_ device: IOBluetoothDevice) -> DeviceBattery? {
        func level(_ key: String) -> Int? {
            guard device.responds(to: NSSelectorFromString(key)) else { return nil }
            return (device.value(forKey: key) as? NSNumber)?.intValue
        }
        let battery = DeviceBattery(left: level("batteryPercentLeft"), right: level("batteryPercentRight"),
                                    caseLevel: level("batteryPercentCase"), single: level("batteryPercentSingle"))
        return battery.isKnown || battery.caseLevel != nil ? battery : nil
    }
}
