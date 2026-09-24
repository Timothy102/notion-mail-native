import Foundation

/// Any JSON value: JSON-RPC envelopes, tool arguments and schemas.
public enum JSON: Sendable, Equatable, Codable {
    case null, bool(Bool), number(Double), string(String), array([JSON]), object([String: JSON])

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([JSON].self) { self = .array(v) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v):
            if let i = Int(exactly: v) { try c.encode(i) } else { try c.encode(v) }
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }

    public subscript(key: String) -> JSON? {
        if case .object(let o) = self { o[key] } else { nil }
    }

    public var string: String? { if case .string(let v) = self { v } else { nil } }
    public var bool: Bool? { if case .bool(let v) = self { v } else { nil } }
    public var int: Int? { if case .number(let v) = self { Int(exactly: v.rounded()) } else { nil } }
    public var array: [JSON]? { if case .array(let v) = self { v } else { nil } }

    /// A string array, or a lone string as a one-element array.
    public var strings: [String]? {
        if let s = string { return [s] }
        return array?.compactMap(\.string)
    }

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()

    /// One line of JSON (strings escape their newlines).
    public var line: String { String(decoding: (try? Self.encoder.encode(self)) ?? Data("null".utf8), as: UTF8.self) }
}

extension JSON: ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByBooleanLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral v: String) { self = .string(v) }
    public init(integerLiteral v: Int) { self = .number(Double(v)) }
    public init(booleanLiteral v: Bool) { self = .bool(v) }
    public init(arrayLiteral v: JSON...) { self = .array(v) }
    public init(dictionaryLiteral v: (String, JSON)...) { self = .object(Dictionary(v) { _, b in b }) }
}
