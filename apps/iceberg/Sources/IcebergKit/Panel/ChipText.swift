import Foundation

/// What a script widget's chip says. A command that prints a bare setup
/// token ("Set LOCATION", "Bad API_KEY") gets a plain note instead, with
/// the token kept for the tooltip.
public enum ChipText {
    public static let needsSetup = "Needs setup"

    public static func shown(_ text: String) -> (text: String, needsSetup: Bool) {
        let words = text.split(separator: " ")
        guard words.count == 2, ["Set", "Bad", "Missing", "No", "Need"].contains(String(words[0])) else { return (text, false) }
        let token = words[1]
        let isToken = token.count >= 2 && token.allSatisfy { ($0.isUppercase && $0.isASCII) || $0.isNumber || $0 == "_" }
            && token.contains(where: \.isLetter)
        return isToken ? (needsSetup, true) : (text, false)
    }
}
