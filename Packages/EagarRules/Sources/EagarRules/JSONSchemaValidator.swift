import Foundation

/// One way an instance fails a schema.
public struct ValidationError: Sendable, Equatable, CustomStringConvertible {
    /// JSON Pointer (RFC 6901) to the failing value; `""` is the document root.
    public let instancePath: String
    /// The schema keyword that failed, for example `enum` or `additionalProperties`.
    public let keyword: String
    /// A human-readable explanation, in British English.
    public let message: String

    public init(instancePath: String, keyword: String, message: String) {
        self.instancePath = instancePath
        self.keyword = keyword
        self.message = message
    }

    public var description: String {
        "\(instancePath.isEmpty ? "(root)" : instancePath): \(message)"
    }
}

/// Why a schema was refused at load time.
public enum SchemaLoadError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The schema text is not JSON.
    case invalidJSON(String)
    /// A keyword outside the supported subset; refusing it stops a rule being silently skipped.
    case unsupportedKeyword(keyword: String, schemaPath: String)
    /// A supported keyword with a malformed value.
    case invalidKeywordValue(keyword: String, schemaPath: String, reason: String)
    /// A `$ref` that is not a local `#/$defs/...` reference or does not resolve.
    case unresolvedReference(ref: String, schemaPath: String)
    /// A `format` other than `uuid` or `date-time`.
    case unsupportedFormat(format: String, schemaPath: String)
    /// A `$ref` that leads back to itself without descending into the value.
    case referenceCycle(ref: String)

    public var description: String {
        switch self {
        case .invalidJSON(let detail):
            "Schema is not valid JSON: \(detail)"
        case .unsupportedKeyword(let keyword, let path):
            "\(path.isEmpty ? "#" : path): keyword \"\(keyword)\" is not supported by this validator"
        case .invalidKeywordValue(let keyword, let path, let reason):
            "\(path.isEmpty ? "#" : path): invalid value for \"\(keyword)\": \(reason)"
        case .unresolvedReference(let ref, let path):
            "\(path.isEmpty ? "#" : path): cannot resolve $ref \"\(ref)\" (only local #/$defs/... references are supported)"
        case .referenceCycle(let ref):
            "$ref \"\(ref)\" leads back to itself without descending into the value"
        case .unsupportedFormat(let format, let path):
            "\(path.isEmpty ? "#" : path): format \"\(format)\" is not supported (supported: uuid, date-time)"
        }
    }
}

/// An in-house validator for the subset of JSON Schema 2020-12 that the eagar schemas use (BD-22, BD-24).
///
/// Supported keywords: `type` (including arrays of types and `integer`), `const`, `enum`,
/// `required`, `properties`, `additionalProperties`, `patternProperties`, `items`, `$ref`
/// (local `#/$defs/...` only), `$defs`, `oneOf`, `anyOf`, `allOf`, `not`, `minimum`, `pattern`
/// and `format` (`uuid` and `date-time`, treated as assertions). `$schema`, `$id`, `$comment`,
/// `title`, `description` and `default` are accepted and ignored. Any other keyword makes the
/// initialiser throw, so the subset can never skip a constraint without anyone noticing.
///
/// `pattern` uses `NSRegularExpression` (ICU syntax), which agrees with ECMA-262 for the
/// patterns in these schemas. Patterns search anywhere in the string, as the standard requires.
public struct JSONSchemaValidator: Sendable {
    /// Keywords that carry constraints.
    public static let supportedKeywords: Set<String> = [
        "type", "const", "enum", "required", "properties", "additionalProperties",
        "patternProperties", "items", "$ref", "$defs", "oneOf", "anyOf", "allOf", "not",
        "minimum", "pattern", "format",
    ]
    /// Keywords accepted and ignored.
    public static let annotationKeywords: Set<String> = [
        "$schema", "$id", "$comment", "title", "description", "default",
    ]
    static let supportedFormats: Set<String> = ["uuid", "date-time"]
    static let typeNames: Set<String> = ["null", "boolean", "object", "array", "number", "string", "integer"]
    static let dialect = "https://json-schema.org/draft/2020-12/schema"
    /// Bound on schema recursion, which also bounds how deeply nested a document may be.
    /// Real eagar documents nest a handful of levels; the bound protects the stack from hostile input.
    static let maximumDepth = 96

    private let root: JSONValue
    private let regexes: [String: NSRegularExpression]

    /// Loads a schema from JSON text.
    public init(schemaData: Data) throws(SchemaLoadError) {
        let schema: JSONValue
        do {
            schema = try JSONDecoder().decode(JSONValue.self, from: schemaData)
        } catch {
            throw .invalidJSON(String(describing: error))
        }
        try self.init(schema: schema)
    }

    /// Loads a schema, checking every keyword against the supported subset and resolving every `$ref`.
    public init(schema: JSONValue) throws(SchemaLoadError) {
        var loader = Loader(root: schema)
        try loader.walk(schema, path: "")
        for (ref, path) in loader.references where Self.resolve(ref, in: schema) == nil {
            throw .unresolvedReference(ref: ref, schemaPath: path)
        }
        try Self.rejectReferenceCycles(in: schema)
        root = schema
        regexes = loader.regexes
    }

    /// Validates `instance`, returning every failure found; an empty array means it conforms.
    public func validate(_ instance: JSONValue) -> [ValidationError] {
        check(instance, against: root, at: "", depth: 0, )
    }

    // MARK: - Loading

    private struct Loader {
        let root: JSONValue
        var references: [(String, String)] = []
        var regexes: [String: NSRegularExpression] = [:]

        mutating func walk(_ schema: JSONValue, path: String) throws(SchemaLoadError) {
            switch schema {
            case .bool:
                return
            case .object(let keywords):
                for key in keywords.keys.sorted() {
                    try visit(key, keywords[key] ?? .null, schemaPath: path)
                }
            default:
                throw .invalidKeywordValue(keyword: "(schema)", schemaPath: path, reason: "a schema must be an object or a boolean")
            }
        }

        private mutating func visit(_ key: String, _ value: JSONValue, schemaPath path: String) throws(SchemaLoadError) {
            let here = path + "/" + JSONPointer.escape(key)
            func invalid(_ reason: String) -> SchemaLoadError {
                .invalidKeywordValue(keyword: key, schemaPath: path, reason: reason)
            }
            switch key {
            case "type":
                let names: [JSONValue]
                if case .array(let list) = value { names = list } else { names = [value] }
                guard !names.isEmpty else { throw invalid("must not be empty") }
                for name in names {
                    guard case .string(let typeName) = name, JSONSchemaValidator.typeNames.contains(typeName) else {
                        throw invalid("unknown type \(name.compactDescription)")
                    }
                }
            case "const", "default":
                return
            case "enum":
                guard case .array(let list) = value, !list.isEmpty else { throw invalid("must be a non-empty array") }
            case "required":
                guard case .array(let list) = value, list.allSatisfy({ if case .string = $0 { true } else { false } }) else {
                    throw invalid("must be an array of strings")
                }
            case "properties", "$defs", "patternProperties":
                guard case .object(let members) = value else { throw invalid("must be an object") }
                for name in members.keys.sorted() {
                    if key == "patternProperties" { try compile(name, keyword: key, schemaPath: path) }
                    try walk(members[name] ?? .null, path: here + "/" + JSONPointer.escape(name))
                }
            case "additionalProperties", "items", "not":
                try walk(value, path: here)
            case "oneOf", "anyOf", "allOf":
                guard case .array(let branches) = value, !branches.isEmpty else { throw invalid("must be a non-empty array") }
                for (index, branch) in branches.enumerated() {
                    try walk(branch, path: here + "/\(index)")
                }
            case "$ref":
                guard case .string(let ref) = value, ref.hasPrefix("#/$defs/") else {
                    throw .unresolvedReference(ref: value.compactDescription, schemaPath: path)
                }
                references.append((ref, path))
            case "minimum":
                guard case .number = value else { throw invalid("must be a number") }
            case "pattern":
                guard case .string(let pattern) = value else { throw invalid("must be a string") }
                try compile(pattern, keyword: key, schemaPath: path)
            case "format":
                guard case .string(let format) = value else { throw invalid("must be a string") }
                guard JSONSchemaValidator.supportedFormats.contains(format) else {
                    throw .unsupportedFormat(format: format, schemaPath: path)
                }
            case "$schema":
                guard value == .string(JSONSchemaValidator.dialect) else {
                    throw invalid("only the 2020-12 dialect is supported")
                }
            case "$id", "$comment", "title", "description":
                guard case .string = value else { throw invalid("must be a string") }
            default:
                throw .unsupportedKeyword(keyword: key, schemaPath: path)
            }
        }

        private mutating func compile(_ pattern: String, keyword: String, schemaPath: String) throws(SchemaLoadError) {
            guard regexes[pattern] == nil else { return }
            do {
                regexes[pattern] = try NSRegularExpression(pattern: pattern)
            } catch {
                throw .invalidKeywordValue(keyword: keyword, schemaPath: schemaPath, reason: "invalid regular expression \"\(pattern)\"")
            }
        }
    }

    /// Refuses `$ref` chains that return to themselves without descending into the value
    /// (through `$ref`, `allOf`, `anyOf`, `oneOf` or `not` only); validating them would never end.
    static func rejectReferenceCycles(in root: JSONValue) throws(SchemaLoadError) {
        func sameLocationRefs(_ schema: JSONValue) -> [String] {
            guard case .object(let keywords) = schema else { return [] }
            var refs: [String] = []
            if case .string(let ref)? = keywords["$ref"] { refs.append(ref) }
            for key in ["allOf", "anyOf", "oneOf"] {
                if case .array(let branches)? = keywords[key] { refs += branches.flatMap(sameLocationRefs) }
            }
            if let negated = keywords["not"] { refs += sameLocationRefs(negated) }
            return refs
        }
        var finished: Set<String> = []
        func visit(_ ref: String, _ stack: [String]) throws(SchemaLoadError) {
            if stack.contains(ref) { throw .referenceCycle(ref: ref) }
            guard !finished.contains(ref), let target = resolve(ref, in: root) else { return }
            for next in sameLocationRefs(target) { try visit(next, stack + [ref]) }
            finished.insert(ref)
        }
        for ref in sameLocationRefs(root) { try visit(ref, []) }
        if case .object(let keywords) = root, case .object(let definitions)? = keywords["$defs"] {
            for name in definitions.keys.sorted() { try visit("#/$defs/" + JSONPointer.escape(name), []) }
        }
    }

    static func resolve(_ ref: String, in root: JSONValue) -> JSONValue? {
        guard ref.hasPrefix("#/") else { return nil }
        var node = root
        for token in ref.dropFirst(2).split(separator: "/", omittingEmptySubsequences: false) {
            guard case .object(let members) = node, let next = members[JSONPointer.unescape(String(token))] else {
                return nil
            }
            node = next
        }
        switch node {
        case .object, .bool: return node
        default: return nil
        }
    }

    // MARK: - Validation
    //
    // The recursive path is split into small functions on purpose: debug builds give a function
    // one stack slot per local across all its branches, and a single large `check` overflowed the
    // 512 KB stack of a cooperative-pool thread at about 19 levels of condition nesting.

    private func check(_ instance: JSONValue, against schema: JSONValue, at path: String, depth: Int) -> [ValidationError] {
        guard depth < Self.maximumDepth else {
            return [ValidationError(instancePath: path, keyword: "$ref", message: "the document is nested too deeply to validate")]
        }
        guard case .object(let keywords) = schema else {
            return schema == .bool(false)
                ? [ValidationError(instancePath: path, keyword: "false", message: "no value is allowed here")]
                : []
        }
        var errors = assertions(instance, keywords, at: path)
        if case .string(let ref)? = keywords["$ref"], let target = Self.resolve(ref, in: root) {
            errors += check(instance, against: target, at: path, depth: depth + 1)
        }
        switch instance {
        case .object(let members): errors += checkObject(members, keywords, at: path, depth: depth)
        case .array(let elements): errors += checkItems(elements, keywords["items"], at: path, depth: depth)
        default: break
        }
        errors += applicators(instance, keywords, at: path, depth: depth)
        return errors
    }

    /// Keywords that look only at this value: `type`, `const`, `enum`, `minimum`, `pattern`, `format`.
    private func assertions(_ instance: JSONValue, _ keywords: [String: JSONValue], at path: String) -> [ValidationError] {
        var errors: [ValidationError] = []
        func fail(_ keyword: String, _ message: String) {
            errors.append(ValidationError(instancePath: path, keyword: keyword, message: message))
        }
        if let type = keywords["type"] {
            checkType(instance, type, fail)
        }
        if let constant = keywords["const"], constant != instance {
            fail("const", "value must equal \(constant.compactDescription)")
        }
        if case .array(let allowed)? = keywords["enum"], !allowed.contains(instance) {
            let list = allowed.map(\.compactDescription).joined(separator: ", ")
            fail("enum", "value \(instance.compactDescription) not in enum [\(list)]")
        }
        switch instance {
        case .number(let value):
            if case .number(let minimum)? = keywords["minimum"], value < minimum {
                fail("minimum", "value \(instance.compactDescription) is less than the minimum \(JSONValue.number(minimum).compactDescription)")
            }
        case .string(let text):
            if case .string(let pattern)? = keywords["pattern"], let regex = regexes[pattern],
               regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) == nil {
                fail("pattern", "value \(instance.compactDescription) does not match pattern \"\(pattern)\"")
            }
            if case .string(let format)? = keywords["format"], !Formats.isValid(text, format: format) {
                fail("format", "value \(instance.compactDescription) is not a valid \(format)")
            }
        default:
            break
        }
        return errors
    }

    private func checkItems(_ elements: [JSONValue], _ items: JSONValue?, at path: String, depth: Int) -> [ValidationError] {
        guard let items else { return [] }
        var errors: [ValidationError] = []
        for (index, element) in elements.enumerated() {
            errors += check(element, against: items, at: path + "/\(index)", depth: depth + 1)
        }
        return errors
    }

    /// `allOf`, `anyOf`, `oneOf` and `not`.
    private func applicators(_ instance: JSONValue, _ keywords: [String: JSONValue], at path: String, depth: Int) -> [ValidationError] {
        var errors: [ValidationError] = []
        if case .array(let branches)? = keywords["allOf"] {
            for branch in branches {
                errors += check(instance, against: branch, at: path, depth: depth + 1)
            }
        }
        if case .array(let branches)? = keywords["anyOf"] {
            let results = branches.map { check(instance, against: $0, at: path, depth: depth + 1) }
            if !results.contains(where: \.isEmpty) {
                errors += closest(results, at: path)
            }
        }
        if case .array(let branches)? = keywords["oneOf"] {
            let results = branches.map { check(instance, against: $0, at: path, depth: depth + 1) }
            let passing = results.indices.filter { results[$0].isEmpty }
            if passing.isEmpty {
                errors += closest(results, at: path)
            } else if passing.count > 1 {
                let list = passing.map(String.init).joined(separator: ", ")
                errors.append(ValidationError(instancePath: path, keyword: "oneOf", message: "value matches more than one oneOf branch (\(list))"))
            }
        }
        if let negated = keywords["not"], check(instance, against: negated, at: path, depth: depth + 1).isEmpty {
            errors.append(ValidationError(instancePath: path, keyword: "not", message: "value must not match the schema under \"not\""))
        }
        return errors
    }

    private func checkType(_ instance: JSONValue, _ type: JSONValue, _ fail: (String, String) -> Void) {
        let names: [String]
        switch type {
        case .string(let name): names = [name]
        case .array(let list): names = list.compactMap { if case .string(let name) = $0 { name } else { nil } }
        default: return
        }
        let matches = names.contains { name in
            switch (name, instance) {
            case ("null", .null), ("boolean", .bool), ("object", .object), ("array", .array),
                 ("string", .string), ("number", .number):
                true
            case ("integer", _):
                instance.isInteger
            default:
                false
            }
        }
        if !matches {
            let expected = names.count == 1 ? names[0] : "one of [\(names.joined(separator: ", "))]"
            fail("type", "expected \(expected), found \(instance.typeName)")
        }
    }

    private func checkObject(
        _ members: [String: JSONValue], _ keywords: [String: JSONValue], at path: String, depth: Int
    ) -> [ValidationError] {
        var errors: [ValidationError] = []
        if case .array(let required)? = keywords["required"] {
            for case .string(let name) in required where members[name] == nil {
                errors.append(ValidationError(instancePath: path, keyword: "required", message: "missing required property \"\(name)\""))
            }
        }
        var properties: [String: JSONValue] = [:]
        if case .object(let declared)? = keywords["properties"] { properties = declared }
        var patterns: [(NSRegularExpression, JSONValue)] = []
        if case .object(let declared)? = keywords["patternProperties"] {
            for pattern in declared.keys.sorted() {
                if let regex = regexes[pattern], let subschema = declared[pattern] { patterns.append((regex, subschema)) }
            }
        }
        let additional = keywords["additionalProperties"]

        for name in members.keys.sorted() {
            guard let value = members[name] else { continue }
            let childPath = path + "/" + JSONPointer.escape(name)
            var evaluated = false
            if let subschema = properties[name] {
                evaluated = true
                errors += check(value, against: subschema, at: childPath, depth: depth + 1, )
            }
            let range = NSRange(name.startIndex..., in: name)
            for (regex, subschema) in patterns where regex.firstMatch(in: name, range: range) != nil {
                evaluated = true
                errors += check(value, against: subschema, at: childPath, depth: depth + 1, )
            }
            guard !evaluated, let additional else { continue }
            if additional == .bool(false) {
                errors.append(ValidationError(instancePath: path, keyword: "additionalProperties", message: "property \"\(name)\" is not allowed"))
            } else {
                errors += check(value, against: additional, at: childPath, depth: depth + 1, )
            }
        }
        return errors
    }

    /// Chooses the failed branch that came nearest to matching, so its errors can be reported.
    ///
    /// A branch that disagrees on the value's own type is furthest away; then one with more
    /// errors on the value itself (missing or extra properties); then one with more errors overall.
    private func closest(_ results: [[ValidationError]], at path: String) -> [ValidationError] {
        func score(_ errors: [ValidationError]) -> (Int, Int, Int) {
            let local = errors.filter { $0.instancePath == path }
            return (local.filter { $0.keyword == "type" }.count, local.count, errors.count)
        }
        return results.min { score($0) < score($1) } ?? []
    }
}

/// RFC 6901 JSON Pointer token escaping.
enum JSONPointer {
    static func escape(_ token: String) -> String {
        token.replacingOccurrences(of: "~", with: "~0").replacingOccurrences(of: "/", with: "~1")
    }

    static func unescape(_ token: String) -> String {
        token.replacingOccurrences(of: "~1", with: "/").replacingOccurrences(of: "~0", with: "~")
    }
}

/// Assertion checks for the `format` values the eagar schemas use.
enum Formats {
    static func isValid(_ text: String, format: String) -> Bool {
        switch format {
        case "uuid": isUUID(text)
        case "date-time": isDateTime(text)
        default: false
        }
    }

    /// RFC 9562 textual form: 8-4-4-4-12 hexadecimal digits.
    static func isUUID(_ text: String) -> Bool {
        text.wholeMatch(of: /[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}/) != nil
    }

    /// RFC 3339 `date-time`, including calendar and range checks.
    static func isDateTime(_ text: String) -> Bool {
        let shape = /([0-9]{4})-([0-9]{2})-([0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(\.[0-9]+)?([Zz]|[+\-]([0-9]{2}):([0-9]{2}))/
        guard let match = text.wholeMatch(of: shape),
              let year = Int(match.1), let month = Int(match.2), let day = Int(match.3),
              let hour = Int(match.4), let minute = Int(match.5), let second = Int(match.6)
        else { return false }
        guard (1...12).contains(month), day >= 1, day <= daysIn(month: month, year: year),
              hour <= 23, minute <= 59, second <= 60
        else { return false }
        if let offsetHours = match.9, let offsetMinutes = match.10 {
            guard let hours = Int(offsetHours), let minutes = Int(offsetMinutes), hours <= 23, minutes <= 59 else { return false }
        }
        return true
    }

    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}
