import ApplicationServices
import LauncherKit

/// Reads and clicks the front app's menu bar through the Accessibility API.
/// Every call waits on the other app, so none of them runs on the main thread,
/// and each gives up after `timeout` instead of the system's six seconds.
enum MenuBarReader {
    static let maxItems = 1_500
    static let maxDepth = 4
    static let timeout: Float = 1

    static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, timeout)
        return app
    }

    static func results(pid: pid_t, app: String) -> [LaunchResult] {
        guard AXIsProcessTrusted() else { return [permissionRow()] }
        return MenuBarItems.results(MenuBarItems.flatten(read(pid: pid)), app: app, pid: pid)
    }

    static func read(pid: pid_t) -> [MenuNode] {
        let app = application(pid)
        guard let bar = element(app, kAXMenuBarAttribute) else { return [] }
        var budget = maxItems
        return kids(bar).compactMap { node($0, depth: 0, budget: &budget) }
    }

    static func node(_ item: AXUIElement, depth: Int, budget: inout Int) -> MenuNode? {
        budget -= 1
        guard budget > 0 else { return nil }
        let title = attribute(item, kAXTitleAttribute) as? String ?? ""
        let enabled = attribute(item, kAXEnabledAttribute) as? Bool ?? true
        var shortcut: KeyShortcut?
        if let key = attribute(item, kAXMenuItemCmdCharAttribute) as? String, !key.isEmpty {
            let modifiers = attribute(item, kAXMenuItemCmdModifiersAttribute) as? Int ?? 0
            shortcut = KeyShortcut(menuKey: key, axModifiers: modifiers)
        }
        var children: [MenuNode] = []
        if depth < maxDepth, let menu = kids(item).first {
            children = kids(menu).compactMap { node($0, depth: depth + 1, budget: &budget) }
        }
        return MenuNode(title: title, enabled: enabled, shortcut: shortcut, children: children)
    }

    /// Finds the item by its titles and presses it. Returns false if it is gone.
    @discardableResult
    static func press(pid: pid_t, path: [String]) -> Bool {
        let app = application(pid)
        guard var current = element(app, kAXMenuBarAttribute) else { return false }
        for (depth, title) in path.enumerated() {
            let candidates = depth == 0 ? kids(current) : kids(current).first.map(kids) ?? []
            guard let match = candidates.first(where: { attribute($0, kAXTitleAttribute) as? String == title }) else { return false }
            current = match
        }
        return AXUIElementPerformAction(current, kAXPressAction as CFString) == .success
    }

    static func permissionRow() -> LaunchResult {
        LaunchResult(
            id: "menubar:permission",
            title: "Allow Accessibility to search menu items",
            subtitle: "System Settings › Privacy & Security › Accessibility",
            icon: .symbol("hand.raised"),
            section: .system,
            keywords: ["menu"],
            actions: [LaunchAction("Open", symbol: "gear", .openURL("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility", bundleID: nil))],
            providerID: "menubar"
        )
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func element(_ parent: AXUIElement, _ name: String) -> AXUIElement? {
        attribute(parent, name).flatMap(asElement)
    }

    static func kids(_ element: AXUIElement) -> [AXUIElement] {
        guard let list = attribute(element, kAXChildrenAttribute) as? [AnyObject] else { return [] }
        return list.compactMap(asElement)
    }

    /// The value as an AXUIElement, checked by its Core Foundation type.
    static func asElement(_ value: AnyObject) -> AXUIElement? {
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
}
