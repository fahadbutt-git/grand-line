#if canImport(SwiftUI)
import SwiftUI

public extension Color {
    init(_ color: ThemeColor) {
        self.init(.sRGB, red: color.red, green: color.green, blue: color.blue, opacity: 1)
    }
}

public extension Theme {
    var colorScheme: ColorScheme { isDark ? .dark : .light }
}
#endif

#if canImport(AppKit)
import AppKit

public extension NSColor {
    convenience init(_ color: ThemeColor) {
        self.init(srgbRed: CGFloat(color.red), green: CGFloat(color.green), blue: CGFloat(color.blue), alpha: 1)
    }
}

public extension Theme {
    /// The system appearance to set on windows, so standard controls match.
    var appearanceName: NSAppearance.Name { isDark ? .darkAqua : .aqua }
}
#endif
