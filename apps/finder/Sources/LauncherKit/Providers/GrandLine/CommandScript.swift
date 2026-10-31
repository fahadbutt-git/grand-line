import Foundation

/// An argument a Grand Line command asks for, from its `# grandline:argN=` line:
/// {"type":"text"|"dropdown","placeholder":"…","data":[…],"optional":true}.
public struct ArgumentSpec: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        case text
        case dropdown
    }

    public var type: Kind
    public var placeholder: String
    public var data: [String]
    public var optional: Bool

    public init(type: Kind, placeholder: String = "", data: [String] = [], optional: Bool = false) {
        self.type = type
        self.placeholder = placeholder
        self.data = data
        self.optional = optional
    }

    enum CodingKeys: String, CodingKey { case type, placeholder, data, optional }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = (try? c.decode(Kind.self, forKey: .type)) ?? .text
        placeholder = (try? c.decode(String.self, forKey: .placeholder)) ?? ""
        data = (try? c.decode([String].self, forKey: .data)) ?? []
        optional = (try? c.decode(Bool.self, forKey: .optional)) ?? false
    }
}

/// A command in ~/.grand-line/bin, described by the comment lines under its first line.
public struct CommandScript: Sendable, Equatable {
    public let name: String
    public let path: String
    public let summary: String
    public let arguments: [ArgumentSpec]

    /// nil for a script without a `# grandline:summary=` line. Only the first 20 lines are read.
    public static func parse(_ text: String, name: String, path: String) -> CommandScript? {
        var summary: String?
        var arguments: [Int: ArgumentSpec] = [:]
        for line in text.split(separator: "\n", omittingEmptySubsequences: false).prefix(20) {
            guard line.hasPrefix("# grandline:") else { continue }
            let body = line.dropFirst("# grandline:".count)
            guard let equals = body.firstIndex(of: "=") else { continue }
            let key = body[..<equals]
            let value = String(body[body.index(after: equals)...]).trimmingCharacters(in: .whitespaces)
            if key == "summary" {
                summary = value
            } else if key.hasPrefix("arg"), let n = Int(key.dropFirst(3)), (1...3).contains(n),
                      let spec = try? JSONDecoder().decode(ArgumentSpec.self, from: Data(value.utf8)) {
                arguments[n] = spec
            }
        }
        guard let summary, !summary.isEmpty else { return nil }
        let ordered = arguments.keys.sorted().map { arguments[$0]! }
        return CommandScript(name: name, path: path, summary: summary, arguments: ordered)
    }

    /// Every described command in a folder, by name.
    public static func scan(_ folder: String, fileManager: FileManager = .default) -> [CommandScript] {
        guard let names = try? fileManager.contentsOfDirectory(atPath: folder) else { return [] }
        return names.sorted().compactMap { name in
            let path = folder + "/" + name
            guard !name.hasPrefix("."), fileManager.isExecutableFile(atPath: path),
                  let handle = FileHandle(forReadingAtPath: path) else { return nil }
            defer { try? handle.close() }
            let head = handle.readData(ofLength: 4_096)
            return parse(String(decoding: head, as: UTF8.self), name: name, path: path)
        }
    }

    /// "reminder ‹remind me to›, ‹in minutes›".
    public var usage: String {
        ([name] + arguments.map { "‹\($0.placeholder.isEmpty ? $0.type.rawValue : $0.placeholder)›" })
            .joined(separator: " ").replacingOccurrences(of: "› ‹", with: "›, ‹")
    }
}

/// Splits what follows a command name into its arguments. With one argument it
/// takes everything; with several they are separated by commas ("buy milk, 30").
/// Double quotes keep a comma inside an argument.
public enum ArgumentSplitter {
    public static func split(_ text: String, count: Int) -> [String] {
        guard count > 1 else {
            let whole = text.trimmingCharacters(in: .whitespaces)
            return whole.isEmpty ? [] : [unquote(whole)]
        }
        var parts: [String] = []
        var current = ""
        var quoted = false
        for character in text {
            if character == "\"" { quoted.toggle(); continue }
            if character == ",", !quoted, parts.count < count - 1 {
                parts.append(current.trimmingCharacters(in: .whitespaces))
                current = ""
                continue
            }
            current.append(character)
        }
        let last = current.trimmingCharacters(in: .whitespaces)
        if !last.isEmpty || !parts.isEmpty { parts.append(last) }
        return parts
    }

    static func unquote(_ text: String) -> String {
        if text.count >= 2, text.hasPrefix("\""), text.hasSuffix("\"") { return String(text.dropFirst().dropLast()) }
        return text
    }
}
