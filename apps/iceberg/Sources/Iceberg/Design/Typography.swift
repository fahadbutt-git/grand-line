import SwiftUI

/// Iceberg's type scale, on macOS's own text styles so each size carries
/// Apple's tracking and leading: 13 pt body, 12 pt callout, 11 pt
/// captions, 10 pt labels. Hierarchy comes from weight. Numbers that
/// change in place use tabular digits so they do not jiggle.
enum TypeScale {
    /// A track title, a settings group: 13 pt semibold.
    static let title = Font.body.weight(.semibold)
    /// Rows, events, reminders: 13 pt.
    static let body = Font.body
    /// The main line of a widget chip, a file name: 12 pt.
    static let callout = Font.callout
    /// Captions, notes, secondary lines: 11 pt.
    static let caption = Font.subheadline
    /// Section captions and the date: 11 pt medium.
    static let captionEmphasis = Font.subheadline.weight(.medium)
    /// The smallest labels: 10 pt medium.
    static let label = Font.caption.weight(.medium)
    /// Times, levels and percentages: 11 pt with tabular digits.
    static let numeral = Font.subheadline.monospacedDigit()
    /// A chip's value: 13 pt medium with tabular digits.
    static let value = Font.body.weight(.medium).monospacedDigit()
    /// File names and code in Settings: 11 pt monospaced.
    static let code = Font.subheadline.monospaced()
}

/// SF Symbol sizes, matched to the text they sit beside. All symbols use
/// the text style's weight, so a row reads as one line.
enum SymbolScale {
    /// Small buttons beside a caption (close, clear): 11 pt semibold.
    static let accessory = Font.subheadline.weight(.semibold)
    /// Icons in rows and chips: 11 pt medium.
    static let row = Font.subheadline.weight(.medium)
    /// Icons in a 13 pt row (settings, reminders).
    static let body = Font.body
    /// Transport controls: 15 pt.
    static let transport = Font.title3
    /// The play and pause button: 17 pt, one step up so it leads.
    static let transportPrimary = Font.title2
    /// An empty state's illustration: 22 pt light.
    static let illustration = Font.title.weight(.light)
}
