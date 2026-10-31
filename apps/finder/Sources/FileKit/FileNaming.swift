import Foundation

/// Finder's names for copies: "Report 2.pdf" when keeping both, "Report copy.pdf"
/// for Duplicate, "untitled folder 2" for a second new folder.
public enum FileNaming {
    /// The first free name in `folder` for keeping both: name, then "name 2", "name 3".
    /// Names in `avoiding` count as taken, for several items going to one folder.
    public static func keepBoth(_ name: String, in folder: URL, avoiding: Set<String> = []) -> String {
        let (stem, ext) = split(name)
        let base = stripNumber(stem)
        var number = 2
        while true {
            let candidate = join("\(base) \(number)", ext)
            if !avoiding.contains(candidate), !exists(candidate, in: folder) { return candidate }
            number += 1
        }
    }

    /// The first free name for Duplicate: "name copy", then "name copy 2".
    public static func duplicate(_ name: String, in folder: URL, avoiding: Set<String> = []) -> String {
        let (stem, ext) = split(name)
        let first = join("\(stem) copy", ext)
        if !avoiding.contains(first), !exists(first, in: folder) { return first }
        var number = 2
        while true {
            let candidate = join("\(stem) copy \(number)", ext)
            if !avoiding.contains(candidate), !exists(candidate, in: folder) { return candidate }
            number += 1
        }
    }

    /// `name` itself when free, otherwise the keep-both name.
    public static func available(_ name: String, in folder: URL, avoiding: Set<String> = []) -> String {
        avoiding.contains(name) || exists(name, in: folder) ? keepBoth(name, in: folder, avoiding: avoiding) : name
    }

    /// Whether a name can be used for a file.
    public static func isValid(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
            && name.utf8.count <= 255
    }

    static func split(_ name: String) -> (String, String) {
        let ext = (name as NSString).pathExtension
        let stem = (name as NSString).deletingPathExtension
        if ext.isEmpty || stem.isEmpty || ext.contains(" ") { return (name, "") }
        return (stem, ext)
    }

    static func join(_ stem: String, _ ext: String) -> String {
        ext.isEmpty ? stem : stem + "." + ext
    }

    /// "Report 2" becomes "Report", so keeping both again gives "Report 3", not "Report 2 2".
    static func stripNumber(_ stem: String) -> String {
        guard let space = stem.lastIndex(of: " ") else { return stem }
        let digits = stem[stem.index(after: space)...]
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }), space != stem.startIndex else {
            return stem
        }
        return String(stem[..<space])
    }

    static func exists(_ name: String, in folder: URL) -> Bool {
        var isFolder: ObjCBool = false
        let path = folder.appendingPathComponent(name).path
        return FileManager.default.fileExists(atPath: path, isDirectory: &isFolder)
            || (try? FileManager.default.destinationOfSymbolicLink(atPath: path)) != nil
    }
}
