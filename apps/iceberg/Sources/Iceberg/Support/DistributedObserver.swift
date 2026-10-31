import Foundation

/// Listens for a distributed notification and hears it at once.
///
/// macOS holds distributed notifications back while an app is not the
/// active one, and Iceberg almost never is (it has no Dock icon), so the
/// block form of `addObserver` would hear `iceberg trigger` or a player's
/// change notice only when the Settings window next came forward. The
/// selector form takes `.deliverImmediately`, which is what this wraps.
final class DistributedObserver: NSObject {
    private let name: Notification.Name
    private let handler: @MainActor (Notification) -> Void

    init(_ name: String, handler: @escaping @MainActor (Notification) -> Void) {
        self.name = Notification.Name(name)
        self.handler = handler
        super.init()
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(received(_:)), name: self.name,
                                                            object: nil, suspensionBehavior: .deliverImmediately)
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self, name: name, object: nil)
    }

    @objc private func received(_ note: Notification) {
        let handler = self.handler
        if Thread.isMainThread {
            MainActor.assumeIsolated { handler(note) }
        } else {
            DispatchQueue.main.async { MainActor.assumeIsolated { handler(note) } }
        }
    }
}
