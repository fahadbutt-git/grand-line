import Foundation

/// A Caps Lock shortcut from keybindings.tsv: keys TAB group TAB description TAB command.
public struct Keybinding: Sendable, Equatable {
    public let keys: String
    public let group: String
    public let description: String
    public let command: String

    /// "Caps + Option + Space" as key caps: ⇪ ⌥ Space.
    public var caps: [String] {
        keys.components(separatedBy: " + ").map { Self.cap($0.trimmingCharacters(in: .whitespaces)) }
    }

    static func cap(_ key: String) -> String {
        switch key.lowercased() {
        case "caps": return "⇪"
        case "option", "alt": return "⌥"
        case "shift": return "⇧"
        case "ctrl", "control": return "⌃"
        case "cmd", "command": return "⌘"
        case "left": return "←"
        case "right": return "→"
        case "up": return "↑"
        case "down": return "↓"
        case "return", "enter": return "↩"
        case "escape", "esc": return "⎋"
        case "tab": return "⇥"
        case "backspace", "delete": return "⌫"
        default: return key
        }
    }
}

public enum KeybindingsFile {
    /// The shipped list, then yours: the same keys replace a shortcut, and
    /// "unbind TAB keys" removes one.
    public static func parse(_ shipped: String, local: String = "") -> [Keybinding] {
        var list = rows(shipped)
        for row in TSV.rows(local) where row.count >= 2 {
            if row[0].lowercased() == "unbind" {
                list.removeAll { $0.keys.lowercased() == row[1].lowercased() }
                continue
            }
            guard let binding = binding(row) else { continue }
            if let index = list.firstIndex(where: { $0.keys.lowercased() == binding.keys.lowercased() }) {
                list[index] = binding
            } else {
                list.append(binding)
            }
        }
        return list
    }

    static func rows(_ text: String) -> [Keybinding] {
        TSV.rows(text).compactMap(binding)
    }

    static func binding(_ row: [String]) -> Keybinding? {
        guard row.count >= 3, !row[0].isEmpty, !row[2].isEmpty else { return nil }
        return Keybinding(keys: row[0], group: row[1], description: row[2], command: row.count > 3 ? row[3] : "")
    }

    public static func load(_ paths: GrandLinePaths) -> [Keybinding] {
        let shipped = (try? String(contentsOfFile: paths.keybindings, encoding: .utf8)) ?? ""
        let local = (try? String(contentsOfFile: paths.bindingsLocal, encoding: .utf8)) ?? ""
        return parse(shipped, local: local)
    }

    public static func results(_ bindings: [Keybinding]) -> [LaunchResult] {
        bindings.map { binding in
            var actions: [LaunchAction] = []
            if !binding.command.isEmpty { actions.append(LaunchAction("Run", symbol: "play", .shell(binding.command))) }
            actions.append(.copy(binding.keys, title: "Copy keys"))
            return LaunchResult(
                id: "key:" + binding.keys,
                title: binding.description,
                subtitle: binding.group,
                icon: .symbol("keyboard"),
                section: .grandLine,
                keywords: [binding.keys, binding.group],
                keys: binding.caps,
                actions: actions,
                providerID: "keybindings"
            )
        }
    }

    public static func provider(_ paths: GrandLinePaths = GrandLinePaths()) -> CatalogProvider {
        CatalogProvider(id: "keybindings", title: "Shortcuts", symbol: "keyboard", globalLimit: 20) {
            results(load(paths))
        }
    }
}
