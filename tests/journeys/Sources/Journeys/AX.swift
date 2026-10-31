import AppKit
import ApplicationServices

/// One accessibility element of another app.
struct Element {
    let ref: AXUIElement

    init(_ ref: AXUIElement) { self.ref = ref }

    static func app(_ pid: pid_t) -> Element {
        let element = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(element, 3)
        return Element(element)
    }

    func attribute(_ name: String) -> AnyObject? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(ref, name as CFString, &value) == .success else { return nil }
        return value
    }

    /// Several attributes in one round trip; a missing one comes back nil.
    func values(_ names: [String]) -> [AnyObject?] {
        var raw: CFArray?
        let err = AXUIElementCopyMultipleAttributeValues(ref, names as CFArray, [], &raw)
        guard err == .success, let array = raw as? [AnyObject], array.count == names.count else {
            return names.map { attribute($0) }
        }
        return array.map { value -> AnyObject? in AXConvert.isError(value) ? nil : value }
    }

    func string(_ name: String) -> String { AXConvert.text(attribute(name)) }
    func elements(_ name: String) -> [Element] { AXConvert.elements(attribute(name)) }
    func element(_ name: String) -> Element? {
        guard let value = attribute(name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return Element(value as! AXUIElement)
    }

    var role: String { string("AXRole") }
    var title: String { string("AXTitle") }
    var children: [Element] { elements("AXChildren") }

    var frame: CGRect? {
        guard let origin = AXConvert.point(attribute("AXPosition")),
              let size = AXConvert.size(attribute("AXSize")) else { return nil }
        return CGRect(origin: origin, size: size)
    }

    @discardableResult
    func perform(_ action: String) -> Bool {
        AXUIElementPerformAction(ref, action as CFString) == .success
    }

    @discardableResult
    func set(_ name: String, _ value: AnyObject) -> Bool {
        AXUIElementSetAttributeValue(ref, name as CFString, value) == .success
    }

    @discardableResult
    func move(to point: CGPoint) -> Bool {
        var p = point
        guard let value = AXValueCreate(.cgPoint, &p) else { return false }
        return set("AXPosition", value)
    }

    @discardableResult
    func resize(to size: CGSize) -> Bool {
        var s = size
        guard let value = AXValueCreate(.cgSize, &s) else { return false }
        return set("AXSize", value)
    }
}

enum AXConvert {
    static func isError(_ value: AnyObject) -> Bool {
        CFGetTypeID(value) == AXValueGetTypeID() && AXValueGetType(value as! AXValue) == .axError
    }

    static func text(_ value: AnyObject?) -> String {
        guard let value else { return "" }
        if let s = value as? String { return s }
        if let a = value as? NSAttributedString { return a.string }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    static func elements(_ value: AnyObject?) -> [Element] {
        guard let array = value as? [AnyObject] else { return [] }
        return array.compactMap { item in
            CFGetTypeID(item) == AXUIElementGetTypeID() ? Element(item as! AXUIElement) : nil
        }
    }

    static func point(_ value: AnyObject?) -> CGPoint? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        var p = CGPoint.zero
        guard AXValueGetType(ax) == .cgPoint, AXValueGetValue(ax, .cgPoint, &p) else { return nil }
        return p
    }

    static func size(_ value: AnyObject?) -> CGSize? {
        guard let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        let ax = value as! AXValue
        var s = CGSize.zero
        guard AXValueGetType(ax) == .cgSize, AXValueGetValue(ax, .cgSize, &s) else { return nil }
        return s
    }
}

/// One element as read at one moment, with its place in the tree.
struct Node {
    let element: Element
    let role: String
    let subrole: String
    let title: String
    let value: String
    let label: String
    let identifier: String
    let placeholder: String
    let help: String
    let frame: CGRect?
    let parent: Int
    let depth: Int
    /// Inside a scroll area, table, outline or list: its frame may lie outside
    /// the window legitimately (scrolled out of view).
    let insideScroll: Bool

    /// What a person reads on it.
    var text: String {
        if !value.isEmpty { return value }
        if !title.isEmpty { return title }
        return label
    }

    var allText: [String] { [value, title, label, placeholder, help].filter { !$0.isEmpty } }

    var center: CGPoint? { frame.map { CGPoint(x: $0.midX, y: $0.midY) } }

    var isVisibleSize: Bool { (frame?.width ?? 0) > 0.5 && (frame?.height ?? 0) > 0.5 }
}

/// A window's elements, read once so every check in a step sees the same thing.
final class Snapshot {
    let nodes: [Node]
    let root: Node?
    let truncated: Bool

    init(nodes: [Node], truncated: Bool) {
        self.nodes = nodes
        self.root = nodes.first
        self.truncated = truncated
    }

    static let attributeNames = [
        "AXRole", "AXSubrole", "AXTitle", "AXValue", "AXDescription", "AXIdentifier",
        "AXPlaceholderValue", "AXHelp", "AXPosition", "AXSize", "AXChildren",
    ]
    static let scrollRoles: Set<String> = ["AXScrollArea", "AXTable", "AXOutline", "AXList", "AXBrowser", "AXCollection"]

    /// Depth-first, in document order. Tables give only their visible rows.
    static func capture(_ root: Element, limit: Int = 5000) -> Snapshot {
        var nodes: [Node] = []
        var stack: [(Element, Int, Int, Bool)] = [(root, -1, 0, false)]
        var truncated = false
        while let item = stack.popLast() {
            let (element, parent, depth, inside) = item
            if nodes.count >= limit { truncated = true; break }
            let v = element.values(attributeNames)
            var frame: CGRect?
            if let origin = AXConvert.point(v[8]), let size = AXConvert.size(v[9]) {
                frame = CGRect(origin: origin, size: size)
            }
            let role = AXConvert.text(v[0])
            let node = Node(
                element: element, role: role, subrole: AXConvert.text(v[1]), title: AXConvert.text(v[2]),
                value: AXConvert.text(v[3]), label: AXConvert.text(v[4]), identifier: AXConvert.text(v[5]),
                placeholder: AXConvert.text(v[6]), help: AXConvert.text(v[7]), frame: frame,
                parent: parent, depth: depth, insideScroll: inside
            )
            let index = nodes.count
            nodes.append(node)
            guard depth < 60, role != "AXMenuBar", role != "AXMenu" else { continue }
            var children = AXConvert.elements(v[10])
            if role == "AXTable" || role == "AXOutline" {
                let visible = element.elements("AXVisibleRows")
                if !visible.isEmpty {
                    let rows = Set(visible.map { CFHash($0.ref) })
                    children = children.filter { child in
                        child.role != "AXRow" || rows.contains(CFHash(child.ref))
                    }
                }
            }
            let childInside = inside || scrollRoles.contains(role)
            for child in children.reversed() {
                stack.append((child, index, depth + 1, childInside))
            }
        }
        return Snapshot(nodes: nodes, truncated: truncated)
    }

    func all(_ role: String? = nil, _ test: (Node) -> Bool = { _ in true }) -> [Node] {
        nodes.filter { (role == nil || $0.role == role) && test($0) }
    }

    func first(_ role: String? = nil, _ test: (Node) -> Bool = { _ in true }) -> Node? {
        nodes.first { (role == nil || $0.role == role) && test($0) }
    }

    func identified(_ id: String) -> Node? { nodes.first { $0.identifier == id } }

    /// Whether node `a` lies inside node `b` in the tree.
    func isDescendant(_ a: Int, of b: Int) -> Bool {
        var cursor = nodes[a].parent
        while cursor >= 0 {
            if cursor == b { return true }
            cursor = nodes[cursor].parent
        }
        return false
    }

    func descendants(of index: Int) -> [Node] {
        var out: [Node] = []
        for i in (index + 1)..<nodes.count {
            if nodes[i].depth <= nodes[index].depth { break }
            out.append(nodes[i])
        }
        return out
    }

    /// Every visible text, for messages.
    var texts: [String] {
        nodes.filter { ["AXStaticText", "AXTextField", "AXButton", "AXCell"].contains($0.role) }
            .map(\.text).filter { !$0.isEmpty }
    }

    /// The first text of each visible table row, in order (the Name column).
    func rowNames() -> [(name: String, node: Node)] {
        var out: [(name: String, node: Node)] = []
        for (index, node) in nodes.enumerated() where node.role == "AXRow" {
            if let text = descendants(of: index).first(where: {
                ($0.role == "AXTextField" || $0.role == "AXStaticText") && !$0.text.isEmpty
            }) {
                out.append((name: text.text, node: text))
            }
        }
        return out
    }
}
