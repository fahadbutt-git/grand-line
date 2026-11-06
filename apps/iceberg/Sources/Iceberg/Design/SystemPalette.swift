import AppKit
import Combine
import SwiftUI
import IcebergKit

/// Iceberg's colours, every one of them the system's own: label colours for
/// text and lines, the accent colour for what is
/// focused or playing, and the system colours (red, green, yellow…) for
/// states. They are dynamic, so each resolves for the appearance it is drawn
/// in: the notch panel is always dark, like the Dynamic Island, because it
/// grows out of the black camera housing; Settings, the drop basket and the
/// menus follow Light and Dark as macOS does. Nothing is read from a theme
/// file, and nothing here changes how macOS looks.
@MainActor
final class SystemPalette: ObservableObject {
    /// The open panel and the closed notch: black, as the camera housing is.
    let panel = Color.black
    /// The notch panel's appearance, whatever macOS uses elsewhere.
    let notchScheme = ColorScheme.dark

    private var observers: [NSObjectProtocol] = []
    private var appearanceObserver: DistributedObserver?

    init() {
        // The accent or highlight colour changed in System Settings, or Light
        // and Dark switched: views that hold a colour as components (the
        // artwork tint, the level bars) are drawn again.
        observers.append(NotificationCenter.default.addObserver(
            forName: NSColor.systemColorsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.objectWillChange.send() }
        })
        appearanceObserver = DistributedObserver("AppleInterfaceThemeChangedNotification") { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Text.
    var foreground: Color { .primary }
    /// Secondary text: captions, times, notes.
    var muted: Color { .secondary }
    /// What is focused or active: the system accent colour.
    var highlight: Color { .accentColor }
    /// A row or plate under the pointer.
    var selection: Color { Color.primary.opacity(0.1) }
    /// Chips and raised things: a quiet fill, as Control Center's modules.
    var card: Color { Color.primary.opacity(0.08) }
    var raised: Color { Color.primary.opacity(0.06) }
    /// Dividers and edges, as light as the system separator. Drawn from the
    /// label colour, so it resolves for the view's own appearance (dark in
    /// the notch whatever macOS uses).
    var line: Color { Color.primary.opacity(0.12) }
    /// Lines with Increase Contrast: a defined edge.
    var strongLine: Color { Color.primary.opacity(0.5) }
    /// The line colour for the current contrast setting.
    func line(increaseContrast: Bool) -> Color { increaseContrast ? strongLine : line }
    /// A window's own background (Settings).
    var background: Color { Color(nsColor: .windowBackgroundColor) }

    /// The accent colour as sRGB components, for the colours worked out
    /// from it (the music's tint for a grey cover).
    var accentRGB: RGB {
        let color = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? NSColor.systemBlue
        return RGB(red: Double(color.redComponent), green: Double(color.greenComponent), blue: Double(color.blueComponent))
    }

    /// Whether macOS shows Dark now, for widget scripts.
    var systemIsDark: Bool {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    /// A widget's colour: a named system colour, or the hex it gave.
    func color(_ c: WidgetColor?) -> Color? {
        guard let c else { return nil }
        switch c {
        case .named(let name): return Self.system(name)
        case .hex(let rgb): return rgb.color
        }
    }

    static func system(_ name: ColorName) -> Color {
        switch name {
        case .foreground: return .primary
        case .muted: return .secondary
        case .highlight, .accent: return .accentColor
        case .red: return .red
        case .green: return .green
        case .yellow: return .yellow
        case .blue: return .blue
        case .magenta: return .purple
        case .cyan: return .cyan
        }
    }
}

extension RGB {
    var color: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: 1) }
}
