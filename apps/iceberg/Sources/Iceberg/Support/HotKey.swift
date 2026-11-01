import Carbon.HIToolbox
import Foundation
import IcebergKit

/// The keyboard shortcut that opens or closes the panel from any app
/// (`toggle_shortcut` in iceberg.toml). It uses Carbon's
/// RegisterEventHotKey, which needs no Accessibility permission and sees
/// only this one key combination. A second one (`HotKey(id: 2)`) holds
/// Escape while the panel is open, and only then.
@MainActor
final class HotKey {
    /// Run when the shortcut is pressed.
    var action: (@MainActor () -> Void)?

    private let hotKeyID: UInt32
    private var ref: EventHotKeyRef?
    private(set) var registered: KeyShortcut?
    private var wanted: KeyShortcut?
    private var suspended = false

    /// One Carbon handler for the app; it finds the HotKey by its id.
    private static var handler: EventHandlerRef?
    private static var live: [UInt32: Weak] = [:]
    private final class Weak { weak var key: HotKey?; init(_ k: HotKey) { key = k } }

    /// Escape, held while the panel is open so it can close it.
    static let escape = KeyShortcut(key: "escape", keyCode: UInt16(kVK_Escape), modifiers: [])

    init(id: UInt32 = 1) {
        hotKeyID = id
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
    }

    fileprivate static func fire(_ id: UInt32) {
        live[id]?.key?.action?()
    }

    /// Registers `shortcut` (nil turns it off). Returns why it could not be
    /// registered, or nil.
    @discardableResult
    func register(_ shortcut: KeyShortcut?) -> String? {
        wanted = shortcut
        guard !suspended else { return nil }
        return apply()
    }

    /// Lets the keys through while Settings records a new shortcut.
    func suspend() {
        suspended = true
        unregister()
    }

    @discardableResult
    func resume() -> String? {
        suspended = false
        return apply()
    }

    private func apply() -> String? {
        unregister()
        guard let shortcut = wanted else { return nil }
        Self.installHandler()
        let id = EventHotKeyID(signature: OSType(0x4943_4247), id: hotKeyID)   // "ICBG"
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &newRef)
        guard status == OSStatus(noErr), let newRef else {
            Log.info("Could not register the shortcut \(shortcut.text) (status \(status))")
            return "\(shortcut.symbols) is taken by macOS or another app. Choose another."
        }
        ref = newRef
        registered = shortcut
        HotKey.live[hotKeyID] = Weak(self)
        return nil
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        registered = nil
    }

    private static func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var pressed = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                           nil, MemoryLayout<EventHotKeyID>.size, nil, &pressed)
            let id = status == OSStatus(noErr) ? pressed.id : 1
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKey.fire(id) }
            }
            return OSStatus(noErr)
        }, 1, &spec, nil, &handler)
    }
}
