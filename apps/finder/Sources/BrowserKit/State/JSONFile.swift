import Foundation

/// A Codable value kept in one JSON file, written atomically.
public struct JSONFile<Value: Codable>: Sendable {
    public let url: URL

    public init(_ url: URL) {
        self.url = url
    }

    public func read() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    public func write(_ value: Value) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(value).write(to: url, options: .atomic)
    }
}
