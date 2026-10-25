import Foundation
@testable import EagarRules

/// Paths into the repository, located from this file so tests read the canonical `docs/schemas/`.
enum Repo {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // EagarRulesTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // EagarRules
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repo root

    static let schemas = root.appending(path: "docs/schemas")
    static let fixtures = schemas.appending(path: "fixtures")

    static func fixtureNames(_ folder: String) -> [String] {
        let url = fixtures.appending(path: folder)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".json") }.sorted()
    }

    static func fixture(_ folder: String, _ name: String) throws -> Data {
        try Data(contentsOf: fixtures.appending(path: folder).appending(path: name))
    }
}

extension JSONValue {
    /// Test convenience: parse JSON text, failing loudly.
    static func json(_ text: String) throws -> JSONValue {
        try JSONValue.parse(Data(text.utf8))
    }

    subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }
}

func validator(_ schemaText: String) throws -> JSONSchemaValidator {
    try JSONSchemaValidator(schemaData: Data(schemaText.utf8))
}
