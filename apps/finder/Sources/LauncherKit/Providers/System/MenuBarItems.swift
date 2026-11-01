import Foundation

/// One node of an app's menu bar, read through Accessibility by the app.
public struct MenuNode: Sendable, Equatable {
    public var title: String
    public var enabled: Bool
    public var shortcut: KeyShortcut?
    public var children: [MenuNode]

    public init(title: String, enabled: Bool = true, shortcut: KeyShortcut? = nil, children: [MenuNode] = []) {
        self.title = title
        self.enabled = enabled
        self.shortcut = shortcut
        self.children = children
    }
}

/// The front app's menu items as rows: "File › Export › PDF", with their shortcuts.
public enum MenuBarItems {
    public static let providerID = "menubar"

    public struct Item: Sendable, Equatable {
        public let path: [String]
        public let shortcut: KeyShortcut?
    }

    /// Every enabled leaf, without the Apple menu, separators or untitled items.
    public static func flatten(_ menuBar: [MenuNode], maxItems: Int = 2_000) -> [Item] {
        var items: [Item] = []
        func walk(_ node: MenuNode, trail: [String]) {
            guard items.count < maxItems, node.enabled else { return }
            let title = node.title.trimmingCharacters(in: .whitespaces)
            guard !title.isEmpty else { return }
            let path = trail + [title]
            if node.children.isEmpty {
                items.append(Item(path: path, shortcut: node.shortcut))
            } else {
                for child in node.children { walk(child, trail: path) }
            }
        }
        for (index, top) in menuBar.enumerated() where !(index == 0 && top.title == "Apple") {
            for child in top.children { walk(child, trail: [top.title]) }
        }
        return items
    }

    public static func results(_ items: [Item], app: String, pid: Int32) -> [LaunchResult] {
        items.map { item in
            LaunchResult(
                id: "menuitem:\(app):" + item.path.joined(separator: "›"),
                title: item.path.last ?? "",
                subtitle: ([app] + item.path.dropLast()).joined(separator: " › "),
                icon: .symbol("filemenu.and.selection"),
                section: .system,
                keywords: Array(item.path.dropLast()),
                keys: item.shortcut.map { [$0.label] } ?? [],
                actions: [LaunchAction("Choose", symbol: "cursorarrow.click", .pressMenuItem(pid: pid, path: item.path))],
                providerID: providerID
            )
        }
    }

    /// Filled by the app with the front app's menus each time the window opens.
    public static func provider() -> CatalogProvider {
        CatalogProvider(id: providerID, title: "Menu items of the front app", symbol: "filemenu.and.selection", globalLimit: 12)
    }
}
