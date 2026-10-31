import ServiceManagement

/// Keeps Iceberg in Login Items to match `launch_at_login` in iceberg.toml.
enum LoginItem {
    static func apply(_ wanted: Bool) {
        let service = SMAppService.mainApp
        do {
            switch (wanted, service.status) {
            case (true, .notRegistered), (true, .notFound):
                try service.register()
            case (false, .enabled), (false, .requiresApproval):
                try service.unregister()
            default:
                break
            }
        } catch {
            // Fails for a copy outside /Applications, which is fine while developing.
            Log.info("Login item not changed: \(error.localizedDescription)")
        }
    }
}
