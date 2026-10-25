import Foundation
import Testing
@testable import EagarRules

/// The expected failure for each invalid fixture. Every file in `fixtures/invalid` must appear here.
private enum Expected: Sendable {
    case schema(path: String, keyword: String)
    case semantic(SemanticIssue.Code)
}

private let invalidExpectations: [String: Expected] = [
    "rules-wrong-format.json": .schema(path: "/format", keyword: "const"),
    "rules-format-version-2.0.json": .schema(path: "/formatVersion", keyword: "pattern"),
    "rules-unknown-root-property.json": .schema(path: "", keyword: "additionalProperties"),
    "rules-missing-document-id.json": .schema(path: "", keyword: "required"),
    "rules-bad-uuid.json": .schema(path: "/documentId", keyword: "format"),
    "rules-bad-date-time.json": .schema(path: "/updatedAt", keyword: "format"),
    "rules-negative-revision.json": .schema(path: "/revision", keyword: "minimum"),
    "rules-revision-not-integer.json": .schema(path: "/revision", keyword: "type"),
    "rules-bad-data-class.json": .schema(path: "/dataClass", keyword: "enum"),
    "rules-condition-op-like.json": .schema(path: "/rules/0/when/op", keyword: "enum"),
    "rules-nested-condition-bad-field.json": .schema(path: "/rules/0/when/all/1/not/field", keyword: "enum"),
    "rules-cross-account-leak-disabled.json": .schema(path: "/guards/crossAccountLeak", keyword: "const"),
    "rules-time-window-bad-pattern.json": .schema(path: "/lanes/0/schedule/0/from", keyword: "pattern"),
    "rules-unknown-lane-property.json": .schema(path: "/lanes/0", keyword: "additionalProperties"),
    "rules-policy-unknown-property.json": .schema(path: "/policy", keyword: "additionalProperties"),
    "rules-playbook-missing-template.json": .schema(path: "/playbooks/0", keyword: "required"),
    "rules-guard-bad-action.json": .schema(path: "/guards/largeReplyAll/action", keyword: "enum"),
    "rules-guard-unknown-property.json": .schema(path: "/guards/tone", keyword: "additionalProperties"),
    "rules-l3-on-local-only-lane.json": .semantic(.autonomyL3OnLocalOnlyLane),
    "rules-adjust-score-missing-amount.json": .schema(path: "/rules/0/then/0", keyword: "required"),
    "rules-set-lane-extra-field.json": .schema(path: "/rules/0/then/0", keyword: "additionalProperties"),
    "rules-notify-missing-level.json": .schema(path: "/rules/1/then/0", keyword: "required"),
    "rules-l3-grant-unknown-lane.json": .semantic(.autonomyL3OnUnknownLane),
    "rules-local-only-lane-cloud-mode.json": .semantic(.localOnlyLaneAllowsCloudProcessing),
    "ledger-with-subject.json": .schema(path: "/events/0", keyword: "additionalProperties"),
    "ledger-bad-event.json": .schema(path: "/events/0/event", keyword: "enum"),
    "ledger-address-in-lane.json": .schema(path: "/events/1/lane", keyword: "pattern"),
    "ledger-missing-summary-field.json": .schema(path: "/summary", keyword: "required"),
]

private func isLedger(_ name: String) -> Bool { name.hasPrefix("ledger-") }

/// Removes a root `"policy": null`, which the codec writes as an absent key (same meaning).
private func normalised(_ value: JSONValue) -> JSONValue {
    guard case .object(var members) = value else { return value }
    if members["policy"] == .null { members["policy"] = nil }
    return .object(members)
}

@Suite("Conformance fixtures")
struct FixtureTests {
    @Test("Fixture folders are populated")
    func foldersArePopulated() {
        #expect(Repo.fixtureNames("valid").count >= 7)
        #expect(Repo.fixtureNames("invalid").count >= 20)
    }

    @Test("Every invalid fixture has an expected failure, and vice versa")
    func expectationsCoverFixtures() {
        #expect(Set(Repo.fixtureNames("invalid")) == Set(invalidExpectations.keys))
    }

    @Test("Valid fixture decodes and round-trips", arguments: Repo.fixtureNames("valid"))
    func validFixtureRoundTrips(name: String) throws {
        let data = try Repo.fixture("valid", name)
        let original = try JSONValue.parse(data)
        let reencoded: Data
        if isLedger(name) {
            let export = try EagarRulesCodec.decodeLedger(data)
            reencoded = try EagarRulesCodec.encodeLedger(export)
            #expect(try EagarRulesCodec.decodeLedger(reencoded) == export)
        } else {
            let document = try EagarRulesCodec.decode(data)
            reencoded = try EagarRulesCodec.encode(document)
            #expect(try EagarRulesCodec.decode(reencoded) == document)
        }
        // JSON-level equality proves nothing (including x- keys) was dropped or invented.
        #expect(normalised(try JSONValue.parse(reencoded)) == normalised(original))
    }

    @Test("Invalid fixture fails with the expected path and keyword", arguments: Repo.fixtureNames("invalid"))
    func invalidFixtureFails(name: String) throws {
        let data = try Repo.fixture("invalid", name)
        let expected = try #require(invalidExpectations[name])
        let error = #expect(throws: RulesError.self) {
            if isLedger(name) {
                _ = try EagarRulesCodec.decodeLedger(data)
            } else {
                _ = try EagarRulesCodec.decode(data)
            }
        }
        switch (expected, error) {
        case (.schema(let path, let keyword), .schemaViolations(let violations)?):
            #expect(violations.count == 1, "one defect per fixture: \(violations)")
            #expect(violations.contains { $0.instancePath == path && $0.keyword == keyword }, "\(violations)")
        case (.semantic(let code), .semanticViolations(let issues)?):
            #expect(issues.map(\.code) == [code])
        default:
            Issue.record("unexpected error for \(name): \(String(describing: error))")
        }
    }

    @Test("A bad action is reported against the branch for its own type", arguments: [
        ("rules-adjust-score-missing-amount.json", "/rules/0/then/0: missing required property \"amount\""),
        ("rules-set-lane-extra-field.json", "/rules/0/then/0: property \"label\" is not allowed"),
        ("rules-notify-missing-level.json", "/rules/1/then/0: missing required property \"level\""),
    ])
    func actionMessageNamesClosestBranch(name: String, message: String) throws {
        let error = #expect(throws: RulesError.self) { try EagarRulesCodec.decode(Repo.fixture("invalid", name)) }
        guard case .schemaViolations(let violations)? = error else {
            Issue.record("expected schema violation, got \(String(describing: error))")
            return
        }
        #expect(violations.map(\.description) == [message])
    }

    @Test("Extension keys survive decode and encode")
    func extensionKeysPreserved() throws {
        let document = try EagarRulesCodec.decode(Repo.fixture("valid", "rules-extensions.json"))
        #expect(document.extensions.keys.sorted() == ["x-note", "x-windows"])
        let encoded = try JSONValue.parse(EagarRulesCodec.encode(document))
        #expect(encoded["x-windows"]?["nested"]?["nothing"] == .null)
        #expect(encoded["x-windows"]?["pinned"] == .array([.number(1), .number(2), .number(3)]))
    }

    @Test("Useful message for a bad condition operator")
    func messageIsUseful() throws {
        do {
            _ = try EagarRulesCodec.decode(Repo.fixture("invalid", "rules-condition-op-like.json"))
            Issue.record("expected failure")
        } catch {
            #expect(String(describing: error).contains("/rules/0/when/op: value \"like\" not in enum [\"equals\", \"notEquals\""))
        }
    }
}
