import Foundation

public struct ParsedQuery: Sendable, Equatable {
    public let root: Node?
    public let issues: [QueryIssue]
    public let sort: SortKey?

    public init(root: Node?, issues: [QueryIssue] = [], sort: SortKey? = nil) {
        self.root = root
        self.issues = issues
        self.sort = sort
    }
}

public indirect enum Node: Sendable, Equatable {
    case term(Term)
    case and([Node])
    case or([Node])
    case not(Node)
    case saved(String)
}

public enum Term: Sendable, Equatable {
    /// Matches the file name or the text content.
    case text(Pattern)
    case field(TextField, Pattern)
    case kind(FileKind)
    /// An absolute path (starting with / or ~) or a bare folder name.
    case folder(String)
    case location(Location)
    case date(DateField, Comparison<DateSpec>)
    case size(Comparison<Int64>)
    case pages(Comparison<Int64>)
}

public struct Pattern: Sendable, Equatable {
    public enum Style: Sendable, Equatable {
        case word, phrase, prefix
    }

    public let text: String
    public let style: Style

    public init(_ text: String, style: Style = .word) {
        self.text = text
        self.style = style
    }

    public static func word(_ text: String) -> Pattern { Pattern(text, style: .word) }
    public static func phrase(_ text: String) -> Pattern { Pattern(text, style: .phrase) }
    public static func prefix(_ text: String) -> Pattern { Pattern(text, style: .prefix) }

    static func parse(_ raw: String, quoted: Bool) -> Pattern? {
        let text = raw.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if quoted { return .phrase(text) }
        var stem = Substring(text)
        while stem.hasSuffix("*") { stem = stem.dropLast() }
        if stem.count < text.count, !stem.isEmpty { return .prefix(String(stem)) }
        return .word(text)
    }
}

public enum TextField: String, Sendable, CaseIterable {
    case name, content, ext, from, tag, author
}

public enum Location: Sendable, Equatable {
    case googleDrive
    /// The home folder, excluding ~/Library/CloudStorage.
    case local
}

public enum DateField: String, Sendable, CaseIterable {
    case modified, created, opened

    public var attribute: String {
        switch self {
        case .modified: return "kMDItemContentModificationDate"
        case .created: return "kMDItemContentCreationDate"
        case .opened: return "kMDItemLastUsedDate"
        }
    }
}

public enum DateSpec: Sendable, Equatable {
    case today
    case yesterday
    /// A point in time N days before now. `week`, `month` and `year` parse to 7, 30 and 365.
    case daysAgo(Int)
    case year(Int)
    case month(year: Int, month: Int)
    case day(year: Int, month: Int, day: Int)

    var isRelative: Bool {
        if case .daysAgo = self { return true }
        return false
    }
}

public enum Comparison<Value: Sendable & Equatable>: Sendable, Equatable {
    case equal(Value)
    case less(Value)
    case lessOrEqual(Value)
    case greater(Value)
    case greaterOrEqual(Value)
    case between(Value, Value)
}

public enum SortKey: String, Sendable, CaseIterable {
    case modified, size, name

    public var attribute: String {
        switch self {
        case .modified: return "kMDItemContentModificationDate"
        case .size: return "kMDItemFSSize"
        case .name: return "kMDItemFSName"
        }
    }

    public var ascending: Bool { self == .name }
}

public enum FileKind: String, Sendable, CaseIterable {
    case pdf, doc, sheet, slides, image, video, audio, folder, app, code, archive, data, text, markdown, email

    public var contentTypes: [String] {
        switch self {
        case .pdf:
            return ["com.adobe.pdf"]
        case .doc:
            return [
                "org.openxmlformats.wordprocessingml.document",
                "com.microsoft.word.doc",
                "org.oasis-open.opendocument.text",
                "public.rtf",
                "com.apple.iwork.pages.sffpages",
            ]
        case .sheet:
            return [
                "org.openxmlformats.spreadsheetml.sheet",
                "com.microsoft.excel.xls",
                "org.oasis-open.opendocument.spreadsheet",
                "com.apple.iwork.numbers.sffnumbers",
                "public.comma-separated-values-text",
            ]
        case .slides:
            return [
                "org.openxmlformats.presentationml.presentation",
                "com.microsoft.powerpoint.ppt",
                "org.oasis-open.opendocument.presentation",
                "com.apple.iwork.keynote.sffkey",
            ]
        case .image: return ["public.image"]
        case .video: return ["public.movie"]
        case .audio: return ["public.audio"]
        case .folder: return ["public.folder"]
        case .app: return ["com.apple.application-bundle"]
        case .code: return ["public.source-code"]
        case .archive: return ["public.archive"]
        case .data:
            return ["public.comma-separated-values-text", "public.tab-separated-values-text", "public.json"]
        case .text: return ["public.plain-text"]
        case .markdown: return ["net.daringfireball.markdown"]
        case .email: return ["com.apple.mail.emlx"]
        }
    }

    public var label: String {
        switch self {
        case .pdf: return "PDF"
        case .doc: return "Word"
        case .sheet: return "spreadsheet"
        case .slides: return "slides"
        case .image: return "image"
        case .video: return "video"
        case .audio: return "audio"
        case .folder: return "folder"
        case .app: return "app"
        case .code: return "code"
        case .archive: return "archive"
        case .data: return "data file"
        case .text: return "plain text"
        case .markdown: return "Markdown"
        case .email: return "email"
        }
    }
}

public struct QueryIssue: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case unknownFilter
        case badDate
        case badSize
        case badValue
        case unbalancedBracket
        case unclosedQuote
        case emptyGroup
        case danglingOperator
        case misplacedFolder
    }

    public let kind: Kind
    public let message: String
    /// Offsets in Characters (grapheme clusters) into the query text.
    public let range: Range<Int>

    public init(kind: Kind, message: String, range: Range<Int>) {
        self.kind = kind
        self.message = message
        self.range = range
    }

    /// The issue's range in UTF-16 units, for AppKit text views.
    public func nsRange(in text: String) -> NSRange {
        let start = text.index(text.startIndex, offsetBy: range.lowerBound, limitedBy: text.endIndex) ?? text.endIndex
        let end = text.index(start, offsetBy: range.count, limitedBy: text.endIndex) ?? text.endIndex
        return NSRange(start..<end, in: text)
    }
}

extension Node {
    var folderMix: (path: Bool, other: Bool) {
        switch self {
        case .term(.folder), .term(.location):
            return (true, false)
        case .term, .saved:
            return (false, true)
        case .and(let children), .or(let children):
            var result = (path: false, other: false)
            for child in children {
                let mix = child.folderMix
                result = (result.path || mix.path, result.other || mix.other)
            }
            return result
        case .not(let inner):
            return inner.folderMix
        }
    }

    var isPathOnly: Bool {
        let mix = folderMix
        return mix.path && !mix.other
    }

    var mixesFolders: Bool {
        if case .and(let children) = self { return children.contains { $0.mixesFolders } }
        let mix = folderMix
        return mix.path && mix.other
    }
}
