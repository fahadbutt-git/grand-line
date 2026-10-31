import Carbon.HIToolbox
import Foundation
import IcebergKit

/// The keyboard shortcut that opens or closes the panel from any app
/// (`toggle_shortcut` in iceberg.toml). It uses Carbon's
/// RegisterEventHotKey, which needs no Accessibility permission and sees
/// only this one key combination.
@MainActor
final class HotKey {
    /// Run when the shortcut is pressed.
    var action: (@MainActor () -> Void)?

    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var registered: KeyShortcut?
    private var wanted: KeyShortcut?
    private var suspended = false

    /// The one HotKey the Carbon handler calls (Iceberg has one shortcut).
    private static weak var current: HotKey?

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
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x4943_4247), id: 1)   // "ICBG"
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers, id,
                                         GetApplicationEventTarget(), 0, &newRef)
        guard status == OSStatus(noErr), let newRef else {
            Log.info("Could not register the shortcut \(shortcut.text) (status \(status))")
            return "\(shortcut.symbols) is taken by macOS or another app. Choose another."
        }
        ref = newRef
        registered = shortcut
        HotKey.current = self
        return nil
    }

    private func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        registered = nil
    }

    private func installHandler() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { HotKey.current?.action?() }
            }
            return OSStatus(noErr)
        }, 1, &spec, nil, &handler)
    }
}
