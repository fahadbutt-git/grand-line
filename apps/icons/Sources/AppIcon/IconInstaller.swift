#if canImport(AppKit)
import AppKit

/// Gives the running app its icon in the theme's colours: the Dock and
/// app switcher at once, and Finder through a custom icon on the bundle.
///
/// The bundle ships AppIcon.icns drawn for Graphite (tools/make-icons.py),
/// so with those colours the custom icon is removed again and the bundle
/// stays as it was built. The custom icon is written only when the colours
/// change, and only into a bundle this user can write to.
@MainActor
public enum AppIconInstaller {
    private static let defaultsKey = "GrandLineAppIconColours"

    public static func apply(_ glyph: IconGlyph, theme: IconTheme, bundle: Bundle = .main) {
        let palette = theme.palette(for: glyph)
        let image = IconRenderer.image(glyph, palette: palette)
        NSApp.applicationIconImage = image
        // A custom Finder icon is written inside the bundle and breaks its code
        // signature, which costs the app its permissions. Off unless asked for;
        // `theme` redraws the bundled icon and re-signs instead.
        guard UserDefaults.standard.bool(forKey: "WriteFinderIcon") else { return }
        setFinderIcon(image, palette: palette, isBundled: palette == IconTheme.bundled.palette(for: glyph), bundle: bundle)
    }

    /// A short key for a palette, to tell whether Finder's icon is current.
    static func key(_ p: IconPalette) -> String {
        [p.tile, p.ink, p.accent, p.soft, p.shade, p.ice].map(\.hex).joined(separator: "-")
    }

    private static func setFinderIcon(_ image: NSImage, palette: IconPalette, isBundled: Bool, bundle: Bundle) {
        let path = bundle.bundlePath
        guard path.hasSuffix(".app"), FileManager.default.isWritableFile(atPath: path) else { return }
        let defaults = UserDefaults.standard
        let last = defaults.string(forKey: defaultsKey)
        if isBundled {
            // Back to the icon the bundle was built with.
            guard last != nil else { return }
            _ = NSWorkspace.shared.setIcon(nil, forFile: path, options: [])
            defaults.removeObject(forKey: defaultsKey)
            return
        }
        let wanted = key(palette)
        // A rebuilt bundle has lost the custom icon, so check for it too.
        let present = FileManager.default.fileExists(atPath: (path as NSString).appendingPathComponent("Icon\r"))
        guard wanted != last || !present else { return }
        if NSWorkspace.shared.setIcon(image, forFile: path, options: []) {
            defaults.set(wanted, forKey: defaultsKey)
        }
    }
}
#endif
