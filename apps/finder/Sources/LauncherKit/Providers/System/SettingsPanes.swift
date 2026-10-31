import Foundation

/// System Settings panes, opened by their x-apple.systempreferences URLs
/// (the extension ids of macOS 15 and later).
public enum SettingsPanes {
    public struct Pane: Sendable, Equatable {
        public let title: String
        public let id: String
        public let keywords: [String]
        public let symbol: String

        public var url: String { "x-apple.systempreferences:" + id }
    }

    public static let all: [Pane] = [
        Pane(title: "Wi-Fi", id: "com.apple.wifi-settings-extension", keywords: ["wireless", "network"], symbol: "wifi"),
        Pane(title: "Bluetooth", id: "com.apple.BluetoothSettings", keywords: ["headphones", "airpods"], symbol: "dot.radiowaves.left.and.right"),
        Pane(title: "Network", id: "com.apple.Network-Settings.extension", keywords: ["ethernet", "proxy", "dns"], symbol: "network"),
        Pane(title: "Notifications", id: "com.apple.Notifications-Settings.extension", keywords: ["alerts", "banners"], symbol: "bell.badge"),
        Pane(title: "Sound", id: "com.apple.Sound-Settings.extension", keywords: ["volume", "output", "input", "microphone"], symbol: "speaker.wave.2"),
        Pane(title: "Focus", id: "com.apple.Focus-Settings.extension", keywords: ["do not disturb"], symbol: "moon"),
        Pane(title: "Screen Time", id: "com.apple.Screen-Time-Settings.extension", keywords: ["limits"], symbol: "hourglass"),
        Pane(title: "General", id: "com.apple.systempreferences.GeneralSettings", keywords: [], symbol: "gear"),
        Pane(title: "About This Mac", id: "com.apple.SystemProfiler.AboutExtension", keywords: ["serial", "version"], symbol: "info.circle"),
        Pane(title: "Software Update", id: "com.apple.Software-Update-Settings.extension", keywords: ["upgrade", "macos"], symbol: "arrow.down.circle"),
        Pane(title: "Storage", id: "com.apple.settings.Storage", keywords: ["disk", "space"], symbol: "internaldrive"),
        Pane(title: "AirDrop & Handoff", id: "com.apple.AirDrop-Handoff-Settings.extension", keywords: ["continuity"], symbol: "airplayaudio"),
        Pane(title: "Login Items & Extensions", id: "com.apple.LoginItems-Settings.extension", keywords: ["startup", "background"], symbol: "power"),
        Pane(title: "Language & Region", id: "com.apple.Localization-Settings.extension", keywords: ["locale", "format"], symbol: "globe"),
        Pane(title: "Date & Time", id: "com.apple.Date-Time-Settings.extension", keywords: ["clock", "time zone"], symbol: "clock"),
        Pane(title: "Sharing", id: "com.apple.Sharing-Settings.extension", keywords: ["file sharing", "screen sharing", "remote login"], symbol: "person.2"),
        Pane(title: "Time Machine", id: "com.apple.Time-Machine-Settings.extension", keywords: ["backup"], symbol: "clock.arrow.circlepath"),
        Pane(title: "Transfer or Reset", id: "com.apple.Transfer-Reset-Settings.extension", keywords: ["erase"], symbol: "arrow.counterclockwise"),
        Pane(title: "Startup Disk", id: "com.apple.Startup-Disk-Settings.extension", keywords: ["boot"], symbol: "externaldrive"),
        Pane(title: "Appearance", id: "com.apple.Appearance-Settings.extension", keywords: ["dark mode", "accent"], symbol: "circle.lefthalf.filled"),
        Pane(title: "Accessibility", id: "com.apple.Accessibility-Settings.extension", keywords: ["zoom", "voiceover"], symbol: "accessibility"),
        Pane(title: "Control Center", id: "com.apple.ControlCenter-Settings.extension", keywords: ["menu bar"], symbol: "switch.2"),
        Pane(title: "Siri", id: "com.apple.Siri-Settings.extension", keywords: ["apple intelligence"], symbol: "mic"),
        Pane(title: "Spotlight", id: "com.apple.Spotlight-Settings.extension", keywords: ["search"], symbol: "magnifyingglass"),
        Pane(title: "Privacy & Security", id: "com.apple.settings.PrivacySecurity.extension", keywords: ["permissions", "filevault"], symbol: "hand.raised"),
        Pane(title: "Accessibility permission", id: "com.apple.preference.security?Privacy_Accessibility", keywords: ["privacy", "allow apps"], symbol: "hand.raised"),
        Pane(title: "Full Disk Access", id: "com.apple.preference.security?Privacy_AllFiles", keywords: ["privacy"], symbol: "hand.raised"),
        Pane(title: "Desktop & Dock", id: "com.apple.Desktop-Settings.extension", keywords: ["dock", "mission control", "hot corners", "stage manager"], symbol: "dock.rectangle"),
        Pane(title: "Displays", id: "com.apple.Displays-Settings.extension", keywords: ["monitor", "resolution", "night shift"], symbol: "display"),
        Pane(title: "Wallpaper", id: "com.apple.Wallpaper-Settings.extension", keywords: ["background"], symbol: "photo"),
        Pane(title: "Battery", id: "com.apple.Battery-Settings.extension", keywords: ["energy", "power"], symbol: "battery.100"),
        Pane(title: "Lock Screen", id: "com.apple.Lock-Screen-Settings.extension", keywords: ["sleep", "password"], symbol: "lock"),
        Pane(title: "Touch ID & Password", id: "com.apple.Touch-ID-Settings.extension", keywords: ["fingerprint"], symbol: "touchid"),
        Pane(title: "Users & Groups", id: "com.apple.Users-Groups-Settings.extension", keywords: ["accounts"], symbol: "person.2"),
        Pane(title: "Passwords", id: "com.apple.Passwords-Settings.extension", keywords: ["keychain"], symbol: "key"),
        Pane(title: "Internet Accounts", id: "com.apple.Internet-Accounts-Settings.extension", keywords: ["mail", "google"], symbol: "at"),
        Pane(title: "Wallet & Apple Pay", id: "com.apple.WalletSettingsExtension", keywords: ["cards"], symbol: "wallet.pass"),
        Pane(title: "Keyboard", id: "com.apple.Keyboard-Settings.extension", keywords: ["shortcuts", "input sources", "dictation"], symbol: "keyboard"),
        Pane(title: "Trackpad", id: "com.apple.Trackpad-Settings.extension", keywords: ["gestures", "click"], symbol: "rectangle.and.hand.point.up.left"),
        Pane(title: "Mouse", id: "com.apple.Mouse-Settings.extension", keywords: ["scroll"], symbol: "computermouse"),
        Pane(title: "Printers & Scanners", id: "com.apple.Print-Scan-Settings.extension", keywords: ["printer"], symbol: "printer"),
        Pane(title: "Apple Account", id: "com.apple.systempreferences.AppleIDSettings", keywords: ["apple id", "icloud"], symbol: "person.crop.circle"),
        Pane(title: "Family", id: "com.apple.Family-Settings.extension", keywords: [], symbol: "person.3"),
    ]

    public static func results() -> [LaunchResult] {
        all.map { pane in
            LaunchResult(
                id: "pane:" + pane.id,
                title: pane.title,
                subtitle: "System Settings",
                icon: .symbol(pane.symbol),
                section: .system,
                keywords: pane.keywords + ["settings"],
                accessory: "Settings",
                actions: [
                    LaunchAction("Open", symbol: "gear", .openURL(pane.url, bundleID: nil)),
                    .copy(pane.url, title: "Copy link"),
                    .favourite,
                ],
                providerID: "settings"
            )
        }
    }

    public static func provider() -> CatalogProvider {
        let provider = CatalogProvider(id: "settings", title: "System Settings", symbol: "gear", extraPrefixes: [.settings], globalLimit: 10)
        provider.replace(results())
        return provider
    }
}
