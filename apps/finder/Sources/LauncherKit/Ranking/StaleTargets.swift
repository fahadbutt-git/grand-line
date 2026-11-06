import Foundation

/// What a remembered row (a recent or a favourite) needs on this Mac to work:
/// an app that handles its URL scheme, an app with its bundle identifier, or
/// the program it runs.
/// A row kept from an app that has since been removed (its settings URL, a
/// menu line that opens it) names a target nothing answers any more; Sight
/// asks macOS about each target and forgets the rows whose target is gone, so
/// they no longer show under Recent.
public enum StaleTargets {
    public enum Target: Hashable, Sendable {
        /// A URL scheme ("sight", "x-apple.systempreferences").
        case scheme(String)
        /// An app's bundle identifier.
        case bundleID(String)
        /// A program run by its full path (a package command).
        case executable(String)
    }

    /// The targets of the row's first action. Files and folders are not
    /// checked here: a drive that is not mounted yet is not gone.
    public static func targets(of result: LaunchResult) -> [Target] {
        guard let command = result.primary?.command else { return [] }
        return targets(of: command)
    }

    public static func targets(of command: ActionCommand) -> [Target] {
        switch command {
        case .open(let target):
            return scheme(of: target).map { [.scheme($0)] } ?? []
        case .openURL(let url, let bundleID):
            if let bundleID, !bundleID.isEmpty { return [.bundleID(bundleID)] }
            return scheme(of: url).map { [.scheme($0)] } ?? []
        case .shell(let line):
            return openTargets(words(line))
        case .run(let executable, let arguments):
            guard (executable as NSString).lastPathComponent == "open" else {
                return executable.hasPrefix("/") ? [.executable(executable)] : []
            }
            return openTargets(["open"] + arguments)
        default:
            return []
        }
    }

    /// The scheme of a URL that is not a file path or a web page, lowercased.
    static func scheme(of text: String) -> String? {
        guard let range = text.range(of: "://"), range.lowerBound > text.startIndex else { return nil }
        let scheme = text[..<range.lowerBound].lowercased()
        guard scheme.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }),
              !["http", "https", "file"].contains(scheme) else { return nil }
        return scheme
    }

    /// `open 'scheme://…'`, `open -b ID`, `open -g -j 'scheme://…'`: what the
    /// macOS open command was asked to reach. Any other line names nothing.
    static func openTargets(_ words: [String]) -> [Target] {
        guard words.first == "open" else { return [] }
        var found: [Target] = []
        var index = 1
        while index < words.count {
            let word = words[index]
            if word == "-b", index + 1 < words.count {
                found.append(.bundleID(words[index + 1]))
                index += 2
                continue
            }
            if word == "-a" || word == "--args" { return found }
            if !word.hasPrefix("-"), let scheme = scheme(of: word) { found.append(.scheme(scheme)) }
            index += 1
        }
        return found
    }

    /// A shell line split into words, with single and double quotes removed.
    /// Anything past a `;`, `&&`, `||` or `|` is left out.
    static func words(_ line: String) -> [String] {
        var words: [String] = []
        var current = ""
        var quote: Character?
        var inWord = false
        for ch in line {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
                continue
            }
            switch ch {
            case "'", "\"":
                quote = ch
                inWord = true
            case " ", "\t":
                if inWord { words.append(current) }
                current = ""
                inWord = false
            case ";", "|", "&":
                if inWord { words.append(current) }
                return words
            default:
                current.append(ch)
                inWord = true
            }
        }
        if inWord { words.append(current) }
        return words
    }
}
