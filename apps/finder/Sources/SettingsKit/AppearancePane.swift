import AppKit
import SwiftUI

/// How tightly rows are packed: each app's own choice, kept in its defaults
/// under `Density`.
public enum Density: String, Sendable, CaseIterable {
    case compact
    case regular
    case comfortable

    /// The key in each app's defaults domain.
    public static let defaultsKey = "Density"

    public var title: String {
        switch self {
        case .compact: return "Compact"
        case .regular: return "Regular"
        case .comfortable: return "Comfortable"
        }
    }

    /// A row height or padding sized for this density, from its regular size.
    public func scaled(_ regular: Double) -> Double {
        switch self {
        case .compact: return (regular * 0.84).rounded()
        case .regular: return regular
        case .comfortable: return (regular * 1.2).rounded()
        }
    }

    /// The app's stored choice, else regular.
    public static func current(defaults: UserDefaults) -> Density {
        defaults.string(forKey: defaultsKey).flatMap(Density.init(rawValue:)) ?? .regular
    }
}

/// Settings, Appearance. The app takes its look from macOS (Light or Dark,
/// the accent colour, the sidebar icon size and the accessibility display
/// options), so the pane only says where those are set and offers the row
/// density, which is the app's own.
public struct AppearancePane: View {
    let density: Density
    let setDensity: (Density) -> Void
    let idPrefix: String

    public init(density: Density, idPrefix: String, setDensity: @escaping (Density) -> Void) {
        self.density = density
        self.idPrefix = idPrefix
        self.setDensity = setDensity
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            SettingsSection("Appearance", note: "Light and Dark, the accent colour and the highlight colour come from macOS.") {
                SettingsRow("Follows System Settings", symbol: "circle.lefthalf.filled") {
                    Button("Open Appearance Settings…") { Self.openSystemAppearance() }
                        .accessibilityIdentifier("\(idPrefix).settings.appearance.system")
                }
            }
            SettingsSection("Density", note: "How tightly this app packs its rows. Kept for this app only.") {
                SettingsRow("Rows") {
                    Picker("Density", selection: Binding(get: { density }, set: { setDensity($0) })) {
                        ForEach(Density.allCases, id: \.self) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                    .accessibilityIdentifier("\(idPrefix).settings.appearance.density")
                }
            }
        }
    }

    /// System Settings, Appearance: only opened, nothing in it is changed.
    static func openSystemAppearance() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Appearance-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
