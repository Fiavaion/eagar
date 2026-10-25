import Foundation

/// An arbitrary JSON value.
///
/// Used for condition leaf values, `x-` extension keys and as the instance model of
/// ``JSONSchemaValidator``. Numbers are held as `Double`, which matches JSON Schema's view
/// that `1` and `1.0` are the same integer.
public enum JSONValue: Sendable, Equatable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// Deepest array/object nesting ``parse(_:)`` accepts. Real documents nest well under 40
    /// levels; the bound keeps hostile input from exhausting the stack inside the decoder.
    public static let maximumNesting = 100

    /// Parses UTF-8 JSON text, refusing nesting deeper than ``maximumNesting``.
    public static func parse(_ data: Data) throws(RulesError) -> JSONValue {
        guard nestingDepth(of: data) <= maximumNesting else {
            throw .invalidJSON("nested deeper than \(maximumNesting) levels")
        }
        do {
            return try JSONDecoder().decode(JSONValue.self, from: data)
        } catch {
            throw .invalidJSON(String(describing: error))
        }
    }

    /// The deepest array/object nesting in JSON text, ignoring brackets inside strings.
    static func nestingDepth(of data: Data) -> Int {
        var depth = 0, deepest = 0, inString = false, escaped = false
        for byte in data {
            if inString {
                if escaped { escaped = false } else if byte == UInt8(ascii: "\\") { escaped = true } else if byte == UInt8(ascii: "\"") { inString = false }
                continue
            }
            switch byte {
            case UInt8(ascii: "\""): inString = true
            case UInt8(ascii: "{"), UInt8(ascii: "["):
                depth += 1
                deepest = max(deepest, depth)
            case UInt8(ascii: "}"), UInt8(ascii: "]"): depth -= 1
            default: break
            }
        }
        return deepest
    }

    /// Whether this is a number with no fractional part (JSON Schema "integer").
    public var isInteger: Bool {
        if case .number(let value) = self { return value.isFinite && value.rounded(.towardZero) == value }
        return false
    }

    /// The JSON Schema type name of this value, reporting integral numbers as "integer".
    var typeName: String {
        switch self {
        case .null: "null"
        case .bool: "boolean"
        case .number: isInteger ? "integer" : "number"
        case .string: "string"
        case .array: "array"
        case .object: "object"
        }
    }

    /// Compact, key-sorted JSON text, used in error messages.
    var compactDescription: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self) else { return typeName }
        return String(decoding: data, as: UTF8.self)
    }
}
