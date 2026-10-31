import Foundation
import UniformTypeIdentifiers

/// The SF Symbol for a row, chosen from the item's type.
public enum FileSymbol {
    public static func name(for item: FileItem) -> String {
        if item.isFolder { return item.isInArchive ? "folder" : folderSymbol(item.name) }
        if item.isAlias { return "arrowshape.turn.up.right" }
        if item.ext == "app" { return "app" }
        guard let id = item.typeIdentifier, let type = UTType(id) else { return byExtension(item.ext) }
        return name(for: type, ext: item.ext)
    }

    static func name(for type: UTType, ext: String) -> String {
        let table: [(UTType, String)] = [
            (.pdf, "doc.richtext"),
            (.image, "photo"),
            (.movie, "film"),
            (.audio, "waveform"),
            (.archive, "doc.zipper"),
            (.sourceCode, "chevron.left.forwardslash.chevron.right"),
            (.spreadsheet, "tablecells"),
            (.presentation, "rectangle.on.rectangle"),
            (.commaSeparatedText, "tablecells"),
            (.json, "curlybraces"),
            (.plainText, "doc.plaintext"),
            (.text, "doc.text"),
            (.diskImage, "externaldrive"),
            (.executable, "terminal"),
        ]
        for (parent, symbol) in table where type.conforms(to: parent) { return symbol }
        return byExtension(ext)
    }

    static func byExtension(_ ext: String) -> String {
        switch ext {
        case "doc", "docx", "odt", "rtf", "pages": return "doc.text"
        case "xls", "xlsx", "ods", "numbers", "csv", "tsv": return "tablecells"
        case "ppt", "pptx", "odp", "key": return "rectangle.on.rectangle"
        case "r", "py", "swift", "js", "ts", "sh", "c", "h", "m": return "chevron.left.forwardslash.chevron.right"
        case "md", "txt": return "doc.plaintext"
        case "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "xz": return "doc.zipper"
        default: return "doc"
        }
    }

    /// Finder's special folders keep their own symbols.
    static func folderSymbol(_ name: String) -> String {
        switch name {
        case "Desktop": return "menubar.dock.rectangle"
        case "Documents": return "doc"
        case "Downloads": return "arrow.down.circle"
        case "Applications": return "square.grid.2x2"
        case "Pictures": return "photo"
        case "Movies": return "film"
        case "Music": return "music.note"
        default: return "folder"
        }
    }
}
