import Foundation

/// Copy as Pathname (Option+Cmd+C): one POSIX path per line. An item inside an
/// archive reads as "/path/to/Data.zip/Figures/plot.png".
public enum CopyPath {
    public static func text(for items: [FileItem]) -> String {
        items.map(\.url.path).joined(separator: "\n")
    }
}
