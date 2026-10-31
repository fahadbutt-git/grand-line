import Foundation

/// Any JSON value, decoded without losing the difference between true and 1.
public enum JSONValue: Decodable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null; return }
        if let b = try? container.decode(Bool.self) { self = .bool(b); return }
        if let d = try? container.decode(Double.self) { self = .number(d); return }
        if let s = try? container.decode(String.self) { self = .string(s); return }
        if let a = try? container.decode([JSONValue].self) { self = .array(a); return }
        if let o = try? container.decode([String: JSONValue].self) { self = .object(o); return }
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "not a JSON value")
    }

    public static func parse(_ data: Data) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: data)
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }
    public var doubleValue: Double? {
        if case .number(let d) = self { return d }
        return nil
    }
    public var boolValue: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }
    public var objectValue: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }

    /// Text for display: strings as they are, whole numbers without ".0".
    public var displayText: String? {
        switch self {
        case .string(let s): return s
        case .number(let d):
            if d.rounded() == d, abs(d) < 1e15 { return String(Int(d)) }
            return String(d)
        case .bool(let b): return b ? "true" : "false"
        default: return nil
        }
    }

    /// The same value in TOML terms, so JSON and TOML files share one validator.
    public var tomlValue: TOMLValue? {
        switch self {
        case .null, .object: return nil
        case .bool(let b): return .bool(b)
        case .string(let s): return .string(s)
        case .number(let d):
            if d.rounded() == d, abs(d) < 1e15 { return .integer(Int(d)) }
            return .float(d)
        case .array(let a): return .array(a.compactMap(\.tomlValue))
        }
    }
}
