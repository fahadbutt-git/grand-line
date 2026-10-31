import Foundation

/// Used when no theme file can be read. The same values as config/themes.
public enum BuiltInThemes {
    /// Apple's dark greys.
    public static let graphite: [String: String] = [
        "LABEL": "Graphite", "MODE": "dark",
        "TERM_BG": "1c1c1e", "TERM_FG": "e5e5e7", "TERM_CURSOR": "a1a1a6", "TERM_SELECTION": "3a3a3c",
        "PALETTE": "2c2c2e ff453a 32d74b ffd60a 0a84ff bf5af2 64d2ff e5e5e7 636366 ff6961 30db5b ffd426 409cff da8fff 70d7ff ffffff",
        "ACCENT_HEX": "98989d", "MUTED": "8e8e93", "BG_LIGHTER": "2c2c2e", "BG_DARKER": "141416", "HIGHLIGHT": "409cff",
        "ICON_STYLE": "line", "ICON_FILES": "409cff", "ICON_SEARCH": "ff6a3d", "ICON_NOTCH": "64d2ff",
        "KIND_STYLE": "tag", "KIND_FOLDER": "64d2ff", "KIND_DOCUMENT": "409cff", "KIND_PDF": "ff6961",
        "KIND_PRESENTATION": "ffb340", "KIND_SPREADSHEET": "30db5b", "KIND_IMAGE": "ff6482", "KIND_VIDEO": "da8fff",
        "KIND_CODE": "ffd426", "KIND_ARCHIVE": "c4a77d", "KIND_TEXT": "98989d",
    ]

    /// Finder's white.
    public static let daylight: [String: String] = [
        "LABEL": "Daylight", "MODE": "light",
        "TERM_BG": "ffffff", "TERM_FG": "1d1d1f", "TERM_CURSOR": "0a6cd6", "TERM_SELECTION": "e3edfb",
        "PALETTE": "1d1d1f d70015 1f7f37 b25000 0040dd 8944ab 0071a4 6e6e73 636366 d1302a 1d8233 946500 0066d6 9a45c8 00789e 1d1d1f",
        "ACCENT_HEX": "0a6cd6", "MUTED": "6e6e73", "BG_LIGHTER": "f5f5f7", "BG_DARKER": "e5e5ea", "HIGHLIGHT": "0a6cd6",
        "ICON_STYLE": "line", "ICON_TILE": "ffffff", "ICON_INK": "1d1d1f",
        "ICON_FILES": "0a6cd6", "ICON_SEARCH": "c8401a", "ICON_NOTCH": "0071a4",
        "KIND_STYLE": "tag", "KIND_FOLDER": "0071a4", "KIND_DOCUMENT": "0040dd", "KIND_PDF": "d70015",
        "KIND_PRESENTATION": "b25000", "KIND_SPREADSHEET": "1f7f37", "KIND_IMAGE": "bf1e5b", "KIND_VIDEO": "8944ab",
        "KIND_CODE": "946500", "KIND_ARCHIVE": "7f6545", "KIND_TEXT": "6e6e73",
    ]

    public static func named(_ name: String) -> Theme? {
        switch name {
        case "graphite": return Theme(name: "graphite", values: graphite)
        case "daylight": return Theme(name: "daylight", values: daylight)
        default: return nil
        }
    }
}
