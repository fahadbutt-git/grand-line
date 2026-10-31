import Foundation

/// What a row draws at its left edge.
public enum ResultIcon: Codable, Hashable, Sendable {
    /// An SF Symbol name.
    case symbol(String)
    /// An app bundle, drawn with the app's own icon.
    case app(String)
    /// One character, such as a symbol from the `:` list.
    case glyph(String)
}
