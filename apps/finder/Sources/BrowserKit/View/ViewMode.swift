import Foundation

/// The five views (R28), chosen per window with Cmd+1 to Cmd+5.
public enum ViewMode: String, Codable, CaseIterable, Sendable {
    case icons
    case list
    case columns
    case gallery
    case panes

    /// 1 to 5, for Cmd+1 to Cmd+5.
    public var number: Int { (ViewMode.allCases.firstIndex(of: self) ?? 0) + 1 }

    public static func numbered(_ number: Int) -> ViewMode? {
        guard (1...allCases.count).contains(number) else { return nil }
        return allCases[number - 1]
    }

    public var title: String {
        switch self {
        case .icons: return "as Icons"
        case .list: return "as List"
        case .columns: return "as Columns"
        case .gallery: return "as Gallery"
        case .panes: return "as Panes"
        }
    }

    public var symbol: String {
        switch self {
        case .icons: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .columns: return "rectangle.split.3x1"
        case .gallery: return "rectangle.bottomthird.inset.filled"
        case .panes: return "rectangle.split.2x1"
        }
    }
}
