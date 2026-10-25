import EagarCore
import Foundation
import Testing
@testable import EagarRules

@Suite("Codec and models")
struct CodecTests {
    @Test("Bundled schemas are byte-identical to docs/schemas", arguments: [
        EagarRulesCodec.rulesSchemaName, EagarRulesCodec.ledgerSchemaName,
    ])
    func resourceParity(name: String) throws {
        let canonical = try Data(contentsOf: Repo.schemas.appending(path: "\(name).json"))
        #expect(try EagarRulesCodec.schemaData(named: name) == canonical)
    }

    @Test("Every schema in docs/schemas is bundled")
    func everySchemaBundled() throws {
        let names = try FileManager.default.contentsOfDirectory(atPath: Repo.schemas.path(percentEncoded: false))
            .filter { $0.hasSuffix(".schema.json") }
            .map { String($0.dropLast(".json".count)) }
            .sorted()
        #expect(names == [EagarRulesCodec.ledgerSchemaName, EagarRulesCodec.rulesSchemaName].sorted())
    }

    @Test("A missing schema resource is reported")
    func missingSchema() {
        #expect(throws: RulesError.self) { try EagarRulesCodec.schemaData(named: "nope") }
    }

    @Test("Text that is not JSON is refused as invalid JSON")
    func notJSON() {
        let error = #expect(throws: RulesError.self) { try EagarRulesCodec.decode(Data("{\"format\":".utf8)) }
        guard case .invalidJSON? = error else {
            Issue.record("expected invalidJSON, got \(String(describing: error))")
            return
        }
    }

    @Test("A model built in code encodes to a valid document and decodes back")
    func buildEncodeDecode() throws {
        let document = RulesDocument(
            schemaURI: "https://example.com/eagar-rules-1.0.schema.json",
            documentId: "0b6f3b9e-1d0c-4f0a-9a3e-7f2c1b9b2a11", revision: 2, updatedAt: "2026-10-25T09:00:00Z",
            author: Author(app: "Eagar", appVersion: "0.1.0", platform: "iOS"),
            dataClass: .personal,
            lanes: [Lane(id: "home", name: "Home", match: LaneMatch(accountAddress: "me@example.com"), weight: 2,
                         boundary: .cloudAllowed, processingMode: .rulesOnly,
                         schedule: [TimeWindow(days: [.sat, .sun], from: "10:00", to: "12:00")], dryRun: true)],
            rules: [Rule(id: "r", description: "d", enabled: false, priority: 3, laneIds: ["home"],
                         when: .any([.leaf(field: .ccCount, op: .gt, value: .number(5)),
                                     .not(.leaf(field: .isReply, op: .equals, value: .bool(true)))]),
                         then: [Action(type: .adjustScore, amount: -5), Action(type: .notify, level: .timeSensitive)])],
            guards: Guards(
                internalDomains: ["example.com"],
                largeReplyAll: LargeReplyAllGuard(enabled: true, action: .confirm, threshold: 8),
                lateNight: LateNightGuard(enabled: true, action: .warn, quietHours: TimeWindow(from: "22:00", to: "07:00"), holdUntil: "08:30"),
                personalData: PersonalDataGuard(enabled: true, action: .block, patterns: [.init(name: "n", regex: "[0-9]+")]),
                crossAccountLeak: .crossAccountLeakRequired),
            playbooks: [Playbook(id: "p", version: 1, name: "P", category: "c", trigger: .init(description: "t"),
                                 requiredFacts: [.init(name: "f", source: .cdbookingBooking)],
                                 template: .init(body: "Hello {{f}}"), aiFill: Playbook.AIFill.none, approvedAt: nil)],
            autonomy: [AutonomyGrant(category: "c", laneId: "home", level: .l1, delayMinutes: 5,
                                     grantedAt: "2026-10-25T09:00:00Z",
                                     evidence: .init(approvals: 3, medianEditRatio: 0.1, guardTriggers: 0, windowDays: 7))],
            policy: InstitutionPolicy(issuer: "IT", appliesToDomains: ["example.com"], maxProcessingMode: .localAI,
                                      forceDryRun: true, maxAutonomy: .l2, learningAllowed: false, profileToCloudAllowed: false),
            extensions: ["x-test": .object(["a": .array([.null, .string("s")])])]
        )
        let data = try EagarRulesCodec.encode(document)
        let json = try JSONValue.parse(data)
        #expect(json["format"] == .string("eagar-rules"))
        guard case .array(let playbooks)? = json["playbooks"] else {
            Issue.record("playbooks missing")
            return
        }
        #expect(playbooks.first?["approvedAt"] == .null, "approvedAt is required, so null is written explicitly")
        #expect(try EagarRulesCodec.decode(data) == document)
    }

    @Test("Encode refuses a document the schema rejects")
    func encodeRefusesSchemaViolation() {
        let document = RulesDocument(documentId: "not-a-uuid", revision: -1, updatedAt: "yesterday", dataClass: .personal)
        let error = #expect(throws: RulesError.self) { try EagarRulesCodec.encode(document) }
        guard case .schemaViolations(let violations)? = error else {
            Issue.record("expected schema violations")
            return
        }
        #expect(Set(violations.map(\.instancePath)) == ["/documentId", "/revision", "/updatedAt"])
    }

    @Test("Ledger export round-trips and refuses invalid content")
    func ledger() throws {
        let export = ApprovalLedgerExport(
            exportedAt: "2026-12-01T09:00:00Z", period: .init(from: "2026-11-01", to: "2026-11-30"),
            events: [LedgerEvent(at: "2026-11-02T09:00:00Z", lane: "home", category: "c", event: .dryRunSent,
                                 origin: .ai, playbookVersion: 1, profileVersion: 0, providerLocality: .anthropicCloud,
                                 editRatio: 0, editClasses: ["none"], guardTriggers: [.tone, .crossAccountLeak],
                                 autonomyLevel: .l0, dryRun: true)],
            summary: LedgerSummary(drafts: 1, approved: 0, rejected: 0, medianEditRatio: 0,
                                   guardCatches: [.tone: 1], sendsWithoutApproval: 0))
        let data = try EagarRulesCodec.encodeLedger(export)
        #expect(try JSONValue.parse(data)["summary"]?["guardCatches"] == .object(["tone": .number(1)]))
        #expect(try EagarRulesCodec.decodeLedger(data) == export)

        var bad = export
        bad.events[0].lane = "Someone Else <someone@example.com>"
        #expect(throws: RulesError.self) { try EagarRulesCodec.encodeLedger(bad) }
    }

    @Test("Ledger schema has no content-bearing fields")
    func ledgerSchemaIsContentFree() throws {
        let text = try String(contentsOf: Repo.schemas.appending(path: "eagar-approval-ledger-1.0.schema.json"), encoding: .utf8)
        for forbidden in ["\"subject\"", "\"body\"", "\"address\"", "\"name\"", "\"from\": { \"type\": \"string\" }"] {
            #expect(!text.contains(forbidden), "\(forbidden)")
        }
    }

    @Test("JSONValue decodes every JSON kind and reports integer-ness")
    func jsonValue() throws {
        let value = try JSONValue.json(#"{"n":null,"b":false,"i":2,"d":2.5,"s":"x","a":[1]}"#)
        #expect(value["n"] == .null)
        #expect(value["b"] == .bool(false))
        #expect(value["i"]?.isInteger == true)
        #expect(value["d"]?.isInteger == false)
        #expect(value["s"]?.isInteger == false)
        #expect(value["a"] == .array([.number(1)]))
        #expect(JSONValue.number(.infinity).isInteger == false)
        #expect(value["s"]?["missing"] == nil)
    }

    @Test("Every RulesError case has a description")
    func errorDescriptions() {
        let errors: [RulesError] = [
            .invalidJSON("x"), .schemaUnavailable("x"),
            .schemaViolations([ValidationError(instancePath: "/a", keyword: "type", message: "m")]),
            .semanticViolations([SemanticIssue(code: .crossAccountLeakDisabled, severity: .error, instancePath: "/g", message: "m")]),
            .decodingFailed("x"), .encodingFailed("x"),
        ]
        for error in errors { #expect(!error.description.isEmpty) }
        #expect(RulesError.schemaViolations([ValidationError(instancePath: "/a", keyword: "type", message: "m")])
            .description.contains("/a: m"))
    }

    @Test("Autonomy levels are ordered")
    func autonomyOrder() {
        #expect(AutonomyLevel.allCases.sorted() == [.l0, .l1, .l2, .l3])
        #expect(AutonomyLevel.l3 > .l2)
    }
}
