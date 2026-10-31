import CoreGraphics
import Foundation

/// Layout checks that hold for any window, run after every step.
enum Layout {
    static let controlRoles: Set<String> = [
        "AXButton", "AXTextField", "AXSearchField", "AXStaticText", "AXCheckBox", "AXPopUpButton",
        "AXRadioButton", "AXMenuButton", "AXSlider", "AXImage",
    ]
    static let inputRoles: Set<String> = ["AXTextField", "AXSearchField"]
    static let clickableRoles: Set<String> = ["AXButton", "AXTextField", "AXSearchField", "AXPopUpButton", "AXCheckBox", "AXMenuButton"]

    static func generic(_ snapshot: Snapshot, window: CGRect) -> [String] {
        var problems: [String] = []
        let nodes = snapshot.nodes
        // Nothing drawn outside the window (scrolled content is allowed to be).
        let bounds = window.insetBy(dx: -2, dy: -2)
        for node in nodes where controlRoles.contains(node.role) && !node.insideScroll && node.isVisibleSize {
            if let frame = node.frame, !bounds.contains(frame) {
                problems.append("\(Ctx.describe(node)) at \(Ctx.rect(frame)) is clipped by the window \(Ctx.rect(window))")
            }
        }
        // No text field drawn over another control.
        let fields = nodes.indices.filter { inputRoles.contains(nodes[$0].role) && !nodes[$0].insideScroll && nodes[$0].isVisibleSize }
        let controls = nodes.indices.filter { clickableRoles.contains(nodes[$0].role) && !nodes[$0].insideScroll && nodes[$0].isVisibleSize }
        for f in fields {
            for c in controls where c != f && !snapshot.isDescendant(c, of: f) && !snapshot.isDescendant(f, of: c) {
                guard let a = nodes[f].frame, let b = nodes[c].frame else { continue }
                let overlap = a.intersection(b)
                if !overlap.isNull, overlap.width > 2, overlap.height > 2 {
                    problems.append("\(Ctx.describe(nodes[f])) \(Ctx.rect(a)) overlaps \(Ctx.describe(nodes[c])) \(Ctx.rect(b))")
                }
            }
        }
        var seen = Set<String>()
        return problems.filter { seen.insert($0).inserted }
    }
}
