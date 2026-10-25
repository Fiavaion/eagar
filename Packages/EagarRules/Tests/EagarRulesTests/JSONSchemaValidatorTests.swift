import Foundation
import Testing
@testable import EagarRules

@Suite("JSONSchemaValidator keywords")
struct JSONSchemaValidatorTests {
    private func errors(_ schema: String, _ instance: String) throws -> [ValidationError] {
        try validator(schema).validate(.json(instance))
    }

    @Test("type: single, array of types, integer vs number", arguments: [
        (#"{"type":"string"}"#, #""a""#, true),
        (#"{"type":"string"}"#, "1", false),
        (#"{"type":"integer"}"#, "3", true),
        (#"{"type":"integer"}"#, "3.0", true),
        (#"{"type":"integer"}"#, "3.5", false),
        (#"{"type":"number"}"#, "3.5", true),
        (#"{"type":"boolean"}"#, "true", true),
        (#"{"type":"boolean"}"#, "0", false),
        (#"{"type":"null"}"#, "null", true),
        (#"{"type":"object"}"#, "{}", true),
        (#"{"type":"array"}"#, "[]", true),
        (#"{"type":"array"}"#, "{}", false),
        (#"{"type":["string","null"]}"#, "null", true),
        (#"{"type":["string","null"]}"#, "2", false),
    ])
    func type(schema: String, instance: String, valid: Bool) throws {
        let found = try errors(schema, instance)
        #expect(found.isEmpty == valid, "\(found)")
        if !valid { #expect(found.first?.keyword == "type") }
    }

    @Test("type message names expected and found types")
    func typeMessage() throws {
        let found = try errors(#"{"type":["string","null"]}"#, "2.5")
        #expect(found.first?.message == "expected one of [string, null], found number")
    }

    @Test("const compares structurally, regardless of key order")
    func const() throws {
        let schema = #"{"const":{"enabled":true,"action":"block"}}"#
        #expect(try errors(schema, #"{"action":"block","enabled":true}"#).isEmpty)
        let found = try errors(schema, #"{"action":"block","enabled":false}"#)
        #expect(found.map(\.keyword) == ["const"])
        #expect(found.first?.message == #"value must equal {"action":"block","enabled":true}"#)
    }

    @Test("enum lists allowed values")
    func enumKeyword() throws {
        #expect(try errors(#"{"enum":["a",1,null]}"#, "1").isEmpty)
        let found = try errors(#"{"enum":["a","b"]}"#, #""c""#)
        #expect(found.first?.description == #"(root): value "c" not in enum ["a", "b"]"#)
    }

    @Test("required reports each missing property at the object")
    func required() throws {
        let found = try errors(#"{"required":["a","b"]}"#, #"{"a":1}"#)
        #expect(found == [ValidationError(instancePath: "", keyword: "required", message: "missing required property \"b\"")])
        #expect(try errors(#"{"required":["a"]}"#, "3").isEmpty, "required ignores non-objects")
    }

    @Test("properties validate child values at their pointer, escaping ~ and /")
    func properties() throws {
        let found = try errors(#"{"properties":{"a/b":{"properties":{"c~d":{"type":"string"}}}}}"#, #"{"a/b":{"c~d":1}}"#)
        #expect(found.map(\.instancePath) == ["/a~1b/c~0d"])
    }

    @Test("additionalProperties false rejects undeclared keys")
    func additionalPropertiesFalse() throws {
        let found = try errors(#"{"properties":{"a":{}},"additionalProperties":false}"#, #"{"a":1,"b":2}"#)
        #expect(found == [ValidationError(instancePath: "", keyword: "additionalProperties", message: "property \"b\" is not allowed")])
    }

    @Test("additionalProperties as a schema validates undeclared values")
    func additionalPropertiesSchema() throws {
        let found = try errors(#"{"additionalProperties":{"type":"string"}}"#, #"{"a":"x","b":2}"#)
        #expect(found.map(\.instancePath) == ["/b"])
    }

    @Test("patternProperties and additionalProperties:false interplay")
    func patternProperties() throws {
        let schema = #"{"properties":{"id":{}},"patternProperties":{"^x-":{},"^n-":{"type":"number"}},"additionalProperties":false}"#
        #expect(try errors(schema, #"{"id":1,"x-anything":{"deep":[1]},"n-count":3}"#).isEmpty)
        let found = try errors(schema, #"{"id":1,"n-count":"three","y-other":true,"prefix-x-":1}"#)
        #expect(found.contains { $0.instancePath == "/n-count" && $0.keyword == "type" })
        #expect(found.contains { $0.message == "property \"y-other\" is not allowed" })
        #expect(found.contains { $0.message == "property \"prefix-x-\" is not allowed" }, "pattern is anchored with ^")
        #expect(found.count == 3)
    }

    @Test("items applies to every element with indexed pointers")
    func items() throws {
        let found = try errors(#"{"items":{"type":"integer"}}"#, #"[1,"two",3,4.5]"#)
        #expect(found.map(\.instancePath) == ["/1", "/3"])
    }

    @Test("$ref resolves local $defs, including recursion")
    func ref() throws {
        let schema = #"""
        {"$ref":"#/$defs/node","$defs":{"node":{"type":"object","additionalProperties":false,
          "properties":{"value":{"type":"integer"},"children":{"type":"array","items":{"$ref":"#/$defs/node"}}}}}}
        """#
        #expect(try errors(schema, #"{"value":1,"children":[{"value":2,"children":[{"value":3}]}]}"#).isEmpty)
        let found = try errors(schema, #"{"children":[{"children":[{"value":"x"}]}]}"#)
        #expect(found.map(\.instancePath) == ["/children/0/children/0/value"])
    }

    @Test("oneOf reports the closest branch's errors")
    func oneOfClosestBranch() throws {
        let schema = #"""
        {"oneOf":[
          {"type":"object","additionalProperties":false,"required":["all"],"properties":{"all":{"type":"array"}}},
          {"type":"object","additionalProperties":false,"required":["field","op"],
           "properties":{"field":{"type":"string"},"op":{"enum":["equals","in"]}}}]}
        """#
        let found = try errors(schema, #"{"field":"subject","op":"like"}"#)
        #expect(found.map(\.instancePath) == ["/op"])
        #expect(found.map(\.keyword) == ["enum"])
    }

    @Test("oneOf prefers a branch of the right type")
    func oneOfPrefersMatchingType() throws {
        let schema = #"{"oneOf":[{"type":"null"},{"type":"object","additionalProperties":false,"properties":{"a":{}}}]}"#
        #expect(try errors(schema, "null").isEmpty)
        let found = try errors(schema, #"{"b":1}"#)
        #expect(found.map(\.keyword) == ["additionalProperties"])
    }

    @Test("oneOf rejects a value matching several branches")
    func oneOfAmbiguous() throws {
        let found = try errors(#"{"oneOf":[{"type":"number"},{"type":"integer"}]}"#, "2")
        #expect(found.map(\.keyword) == ["oneOf"])
        #expect(found.first?.message.contains("(0, 1)") == true)
    }

    @Test("Nested oneOf through $ref reports the deepest relevant failure")
    func nestedOneOf() throws {
        let schema = #"""
        {"$ref":"#/$defs/c","$defs":{"c":{"oneOf":[
          {"type":"object","additionalProperties":false,"required":["not"],"properties":{"not":{"$ref":"#/$defs/c"}}},
          {"type":"object","additionalProperties":false,"required":["v"],"properties":{"v":{"enum":[1,2]}}}]}}}
        """#
        #expect(try errors(schema, #"{"not":{"not":{"v":1}}}"#).isEmpty)
        let found = try errors(schema, #"{"not":{"not":{"v":3}}}"#)
        #expect(found == [ValidationError(instancePath: "/not/not/v", keyword: "enum", message: "value 3 not in enum [1, 2]")])
    }

    @Test("anyOf passes when one branch passes and reports the closest otherwise")
    func anyOf() throws {
        let schema = #"{"anyOf":[{"type":"string","pattern":"^a"},{"type":"integer"}]}"#
        #expect(try errors(schema, #""abc""#).isEmpty)
        #expect(try errors(schema, "4").isEmpty)
        let found = try errors(schema, #""xyz""#)
        #expect(found.map(\.keyword) == ["pattern"])
    }

    @Test("allOf accumulates errors from every branch")
    func allOf() throws {
        let found = try errors(#"{"allOf":[{"required":["a"]},{"required":["b"]}]}"#, "{}")
        #expect(found.count == 2)
    }

    @Test("not fails when the inner schema passes")
    func not() throws {
        #expect(try errors(#"{"not":{"type":"string"}}"#, "1").isEmpty)
        #expect(try errors(#"{"not":{"type":"string"}}"#, #""s""#).map(\.keyword) == ["not"])
    }

    @Test("minimum is inclusive")
    func minimum() throws {
        #expect(try errors(#"{"minimum":0}"#, "0").isEmpty)
        #expect(try errors(#"{"minimum":0}"#, "-0.5").map(\.keyword) == ["minimum"])
        #expect(try errors(#"{"minimum":0}"#, #""text""#).isEmpty, "minimum ignores non-numbers")
    }

    @Test("pattern searches unanchored unless the pattern anchors")
    func pattern() throws {
        #expect(try errors(#"{"pattern":"b"}"#, #""abc""#).isEmpty)
        #expect(try errors(#"{"pattern":"^b"}"#, #""abc""#).map(\.keyword) == ["pattern"])
    }

    @Test("Boolean schemas", arguments: [("true", true), ("false", false)])
    func booleanSchemas(schema: String, valid: Bool) throws {
        let found = try errors(#"{"properties":{"a":"# + schema + "}}", #"{"a":1}"#)
        #expect(found.isEmpty == valid)
    }

    @Test("format uuid", arguments: [
        ("0b6f3b9e-1d0c-4f0a-9a3e-7f2c1b9b2a11", true),
        ("0B6F3B9E-1D0C-4F0A-9A3E-7F2C1B9B2A11", true),
        ("0b6f3b9e1d0c4f0a9a3e7f2c1b9b2a11", false),
        ("0b6f3b9e-1d0c-4f0a-9a3e-7f2c1b9b2a1", false),
        ("zzzzzzzz-1d0c-4f0a-9a3e-7f2c1b9b2a11", false),
    ])
    func uuid(text: String, valid: Bool) throws {
        let found = try validator(#"{"format":"uuid"}"#).validate(.string(text))
        #expect(found.isEmpty == valid)
    }

    @Test("format date-time", arguments: [
        ("2026-10-25T09:00:00Z", true),
        ("2026-10-25t09:00:00z", true),
        ("2026-10-25T09:00:00.123+01:00", true),
        ("2024-02-29T00:00:00Z", true),
        ("2000-02-29T00:00:00Z", true),
        ("1900-02-29T00:00:00Z", false),
        ("2026-02-29T00:00:00Z", false),
        ("2026-04-31T00:00:00Z", false),
        ("2026-13-01T00:00:00Z", false),
        ("2026-10-25T24:00:00Z", false),
        ("2026-10-25T09:60:00Z", false),
        ("2026-10-25T09:00:61Z", false),
        ("2026-10-25T09:00:00+24:00", false),
        ("2026-10-25T09:00:00", false),
        ("2026-10-25", false),
    ])
    func dateTime(text: String, valid: Bool) throws {
        let found = try validator(#"{"format":"date-time"}"#).validate(.string(text))
        #expect(found.isEmpty == valid)
    }

    @Test("format ignores non-strings")
    func formatNonString() throws {
        #expect(try errors(#"{"type":["string","null"],"format":"date-time"}"#, "null").isEmpty)
    }

    @Test("Annotations are accepted and ignored")
    func annotations() throws {
        let schema = #"{"$schema":"https://json-schema.org/draft/2020-12/schema","$id":"x","$comment":"c","title":"t","description":"d","default":5}"#
        #expect(try errors(schema, #""anything""#).isEmpty)
    }

    @Test("Unsupported keywords fail loudly at load time", arguments: [
        "if", "then", "else", "maximum", "minLength", "maxItems", "uniqueItems", "unevaluatedProperties",
        "propertyNames", "dependentRequired", "prefixItems", "contains", "$anchor", "$dynamicRef",
    ])
    func unsupportedKeyword(keyword: String) {
        #expect(throws: SchemaLoadError.unsupportedKeyword(keyword: keyword, schemaPath: "/properties/a")) {
            try validator(#"{"properties":{"a":{"\#(keyword)":1}}}"#)
        }
    }

    @Test("Malformed schemas are refused at load time", arguments: [
        #"{"type":"text"}"#,
        #"{"type":[]}"#,
        #"{"enum":[]}"#,
        #"{"required":[1]}"#,
        #"{"properties":[]}"#,
        #"{"oneOf":[]}"#,
        #"{"minimum":"0"}"#,
        #"{"pattern":"("}"#,
        #"{"patternProperties":{"[":{}}}"#,
        #"{"pattern":1}"#,
        #"{"format":2}"#,
        #"{"$id":3}"#,
        #"{"$schema":"http://json-schema.org/draft-07/schema#"}"#,
        #"{"items":3}"#,
        "[1]",
    ])
    func malformed(schema: String) {
        #expect(throws: SchemaLoadError.self) { try validator(schema) }
    }

    @Test("Unsupported formats fail at load time")
    func unsupportedFormat() {
        #expect(throws: SchemaLoadError.unsupportedFormat(format: "email", schemaPath: "")) {
            try validator(#"{"format":"email"}"#)
        }
    }

    @Test("References must be local $defs and must resolve", arguments: [
        ##"{"$ref":"#/$defs/missing","$defs":{}}"##,
        ##"{"$ref":"other.json#/x"}"##,
        ##"{"$ref":"#/properties/a","properties":{"a":{}}}"##,
        ##"{"$ref":5}"##,
        ##"{"$ref":"#/$defs/n","$defs":{"n":{"enum":[1]},"m":3}}"##,
    ])
    func badReference(schema: String) {
        #expect(throws: SchemaLoadError.self) { try validator(schema) }
    }

    @Test("Schema text that is not JSON is refused")
    func schemaNotJSON() {
        #expect(throws: SchemaLoadError.self) { try JSONSchemaValidator(schemaData: Data("{".utf8)) }
    }

    @Test("Reference cycles that consume nothing are refused at load time", arguments: [
        ##"{"$ref":"#/$defs/a","$defs":{"a":{"$ref":"#/$defs/a"}}}"##,
        ##"{"$defs":{"a":{"anyOf":[{"$ref":"#/$defs/b"}]},"b":{"not":{"allOf":[{"$ref":"#/$defs/a"}]}}}}"##,
        ##"{"$defs":{"a":{"oneOf":[{"$ref":"#/$defs/a"}]}}}"##,
    ])
    func referenceCycle(schema: String) {
        #expect(throws: SchemaLoadError.self) { try validator(schema) }
    }

    @Test("Recursion that descends into the value is not a cycle")
    func recursionIsNotACycle() throws {
        _ = try validator(##"{"$defs":{"a":{"oneOf":[{"$ref":"#/$defs/b"},{"items":{"$ref":"#/$defs/a"}}]},"b":{"properties":{"x":{"$ref":"#/$defs/a"}}}}}"##)
    }

    @Test("Hostile nesting is refused before decoding")
    func parseDepthLimit() {
        let text = String(repeating: "[", count: 5000) + String(repeating: "]", count: 5000)
        let error = #expect(throws: RulesError.self) { try EagarRulesCodec.decode(Data(text.utf8)) }
        guard case .invalidJSON(let detail)? = error else {
            Issue.record("expected invalidJSON, got \(String(describing: error))")
            return
        }
        #expect(detail.contains("nested deeper"))
        let deepest = String(repeating: "[", count: JSONValue.maximumNesting) + String(repeating: "]", count: JSONValue.maximumNesting)
        #expect(throws: Never.self) { try JSONValue.parse(Data(deepest.utf8)) }
        #expect(JSONValue.nestingDepth(of: Data(#"{"a":"[[[{{\"]]","b":[[1]]}"#.utf8)) == 3, "brackets in strings are ignored")
    }

    @Test("Validation stops at its depth limit instead of exhausting the stack")
    func validationDepthLimit() throws {
        var condition = JSONValue.object(["field": .string("subject"), "op": .string("equals"), "value": .string("x")])
        for _ in 0..<90 { condition = .object(["not": condition]) }
        let document = try JSONValue.json(#"{"format":"eagar-rules","formatVersion":"1.0","documentId":"0b6f3b9e-1d0c-4f0a-9a3e-7f2c1b9b2a11","revision":0,"updatedAt":"2026-10-25T09:00:00Z","dataClass":"personal"}"#)
        guard case .object(var members) = document else { return }
        members["rules"] = .array([.object(["id": .string("r"), "then": .array([]), "when": condition])])
        let violations = try EagarRulesCodec.rulesValidator.get().validate(.object(members))
        #expect(violations.contains { $0.message.contains("nested too deeply") }, "\(violations)")
    }

    @Test("Realistic nesting (20 levels of conditions) validates")
    func realisticNesting() throws {
        var condition = #"{"field":"subject","op":"equals","value":"x"}"#
        for level in 0..<20 { condition = level.isMultiple(of: 2) ? #"{"not":"# + condition + "}" : #"{"all":["# + condition + "]}" }
        let document = #"{"format":"eagar-rules","formatVersion":"1.0","documentId":"0b6f3b9e-1d0c-4f0a-9a3e-7f2c1b9b2a11","revision":0,"updatedAt":"2026-10-25T09:00:00Z","dataClass":"personal","rules":[{"id":"r","then":[],"when":"# + condition + "}]}"
        _ = try EagarRulesCodec.decode(Data(document.utf8))
    }

    @Test("Load errors describe where they are")
    func loadErrorDescriptions() {
        let errors: [SchemaLoadError] = [
            .invalidJSON("x"),
            .unsupportedKeyword(keyword: "if", schemaPath: ""),
            .invalidKeywordValue(keyword: "enum", schemaPath: "/a", reason: "r"),
            .unresolvedReference(ref: "#/x", schemaPath: ""),
            .unsupportedFormat(format: "email", schemaPath: "/b"),
            .referenceCycle(ref: "#/$defs/a"),
        ]
        for error in errors { #expect(!error.description.isEmpty) }
        #expect(SchemaLoadError.unsupportedKeyword(keyword: "if", schemaPath: "/p").description.hasPrefix("/p: keyword \"if\""))
    }

    @Test("Both published schemas load under the subset")
    func publishedSchemasLoad() throws {
        for name in ["eagar-rules-1.0.schema.json", "eagar-approval-ledger-1.0.schema.json"] {
            _ = try JSONSchemaValidator(schemaData: Data(contentsOf: Repo.schemas.appending(path: name)))
        }
    }
}
