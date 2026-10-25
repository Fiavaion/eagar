import Foundation
import Testing

/// NFR-L10N-01/02: every user-facing string is in the catalog, with British English as the
/// source and an Irish (`ga`) pseudo-localisation scaffold.
struct StringCatalogTests {
    private func catalog() throws -> [String: Any] {
        let url = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../Eagar/Localizable.xcstrings").standardized
        return try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }

    @Test func sourceLanguageIsBritishEnglish() throws {
        #expect(try catalog()["sourceLanguage"] as? String == "en-GB")
    }

    @Test func everyStringHasAnIrishScaffold() throws {
        let strings = try #require(try catalog()["strings"] as? [String: Any])
        #expect(!strings.isEmpty)
        var missing: [String] = []
        for (key, value) in strings {
            let entry = value as? [String: Any] ?? [:]
            if entry["shouldTranslate"] as? Bool == false { continue }
            let localizations = entry["localizations"] as? [String: Any] ?? [:]
            if localizations["ga"] == nil { missing.append(key) }
        }
        #expect(missing.isEmpty, "missing ga: \(missing.sorted().prefix(10))")
    }
}
