import EagarCore
import Foundation
import Testing
@testable import EagarRules

@Suite("Appendix F semantic rules")
struct RulesSemanticValidatorTests {
    private func document(
        grants: [AutonomyGrant], maxAutonomy: AutonomyLevel? = nil, guards: Guards? = nil
    ) -> RulesDocument {
        RulesDocument(
            documentId: "0b6f3b9e-1d0c-4f0a-9a3e-7f2c1b9b2a11", revision: 1, updatedAt: "2026-10-25T09:00:00Z",
            dataClass: .college,
            lanes: [
                Lane(id: "work", name: "Work", match: LaneMatch(accountDomain: "example.ie"), weight: 1,
                     boundary: .localOnly, processingMode: .localAI),
                Lane(id: "home", name: "Home", match: LaneMatch(accountAddress: "me@example.com"), weight: 1,
                     boundary: .cloudAllowed, processingMode: .cloudAllowed),
            ],
            guards: guards,
            autonomy: grants,
            policy: maxAutonomy.map { InstitutionPolicy(maxAutonomy: $0) }
        )
    }

    private func grant(_ lane: String, _ level: AutonomyLevel) -> AutonomyGrant {
        AutonomyGrant(category: "c", laneId: lane, level: level, grantedAt: "2026-10-25T09:00:00Z")
    }

    @Test("Rule 1: L3 on a localOnly lane is refused")
    func l3OnLocalOnly() {
        let issues = RulesSemanticValidator.issues(in: document(grants: [grant("home", .l3), grant("work", .l3)]))
        #expect(issues.map(\.code) == [.autonomyL3OnLocalOnlyLane])
        #expect(issues.first?.instancePath == "/autonomy/1")
        #expect(issues.first?.severity == .error)
    }

    @Test("Rule 1: L2 on a localOnly lane and L3 on a cloudAllowed lane are allowed", arguments: [
        ("work", AutonomyLevel.l2), ("home", .l3), ("work", .l0),
    ])
    func allowedGrants(lane: String, level: AutonomyLevel) {
        #expect(RulesSemanticValidator.issues(in: document(grants: [grant(lane, level)])).isEmpty)
    }

    @Test("Rule 1: a grant above policy.maxAutonomy is flagged as ignored, not refused")
    func abovePolicyMaximum() throws {
        let doc = document(grants: [grant("home", .l2), grant("home", .l1)], maxAutonomy: .l1)
        let issues = RulesSemanticValidator.issues(in: doc)
        #expect(issues.map(\.code) == [.autonomyAbovePolicyMaximum])
        #expect(issues.first?.severity == .warning)
        #expect(RulesSemanticValidator.errors(in: doc).isEmpty)
        let data = try EagarRulesCodec.encode(doc)
        #expect(try EagarRulesCodec.decode(data) == doc)
    }

    @Test("Rule 1: L3 on localOnly is refused by encode as well as decode")
    func encodeRefusesL3OnLocalOnly() {
        #expect(throws: RulesError.self) {
            try EagarRulesCodec.encode(document(grants: [grant("work", .l3)]))
        }
    }

    @Test("Rule 1: L3 on a lane the document does not define is refused, by decode and encode")
    func l3OnUnknownLane() {
        let doc = document(grants: [grant("home", .l3), grant("missing", .l3)])
        let issues = RulesSemanticValidator.issues(in: doc)
        #expect(issues.map(\.code) == [.autonomyL3OnUnknownLane])
        #expect(issues.first?.instancePath == "/autonomy/1")
        #expect(issues.first?.severity == .error)
        let error = #expect(throws: RulesError.self) { try EagarRulesCodec.encode(doc) }
        if case .semanticViolations(let refused)? = error {
            #expect(refused.map(\.code) == [.autonomyL3OnUnknownLane])
        } else {
            Issue.record("expected semantic violation, got \(String(describing: error))")
        }
    }

    @Test("Rule 1: below L3, a grant on an undefined lane is not refused", arguments: [AutonomyLevel.l0, .l1, .l2])
    func belowL3OnUnknownLane(level: AutonomyLevel) {
        #expect(RulesSemanticValidator.issues(in: document(grants: [grant("missing", level)])).isEmpty)
    }

    @Test("BD-05: a localOnly lane cannot allow cloud processing, by decode and encode")
    func localOnlyLaneCloudMode() {
        var doc = document(grants: [])
        doc.lanes?[0].processingMode = .cloudAllowed
        let issues = RulesSemanticValidator.issues(in: doc)
        #expect(issues.map(\.code) == [.localOnlyLaneAllowsCloudProcessing])
        #expect(issues.first?.instancePath == "/lanes/0")
        #expect(issues.first?.severity == .error)
        #expect(issues.first?.description.hasPrefix("/lanes/0: lane \"work\" has boundary localOnly") == true)
        let error = #expect(throws: RulesError.self) { try EagarRulesCodec.encode(doc) }
        if case .semanticViolations(let refused)? = error {
            #expect(refused.map(\.code) == [.localOnlyLaneAllowsCloudProcessing])
        } else {
            Issue.record("expected semantic violation, got \(String(describing: error))")
        }
    }

    @Test("BD-05: a localOnly lane may be rules-only or local AI", arguments: [ProcessingMode.rulesOnly, .localAI])
    func localOnlyLaneLocalModes(mode: ProcessingMode) {
        var doc = document(grants: [])
        doc.lanes?[0].processingMode = mode
        #expect(RulesSemanticValidator.issues(in: doc).isEmpty)
    }

    @Test("Rule 3: crossAccountLeak cannot be disabled or softened", arguments: [
        GuardSetting(enabled: false, action: .block),
        GuardSetting(enabled: true, action: .warn),
        GuardSetting(enabled: true, action: nil),
        GuardSetting(),
    ])
    func crossAccountLeak(setting: GuardSetting) {
        let doc = document(grants: [], guards: Guards(crossAccountLeak: setting))
        #expect(RulesSemanticValidator.issues(in: doc).map(\.code) == [.crossAccountLeakDisabled])
        let error = #expect(throws: RulesError.self) { try EagarRulesCodec.encode(doc) }
        if case .semanticViolations(let issues)? = error {
            #expect(issues.map(\.code) == [.crossAccountLeakDisabled])
        } else {
            Issue.record("expected semantic violation, got \(String(describing: error))")
        }
    }

    @Test("Rule 3: the schema also refuses a disabled crossAccountLeak (defence in depth)")
    func crossAccountLeakSchema() throws {
        let data = try Repo.fixture("invalid", "rules-cross-account-leak-disabled.json")
        let error = #expect(throws: RulesError.self) { try EagarRulesCodec.decode(data) }
        guard case .schemaViolations(let violations)? = error else {
            Issue.record("expected schema violation")
            return
        }
        #expect(violations.map(\.keyword) == ["const"])
    }

    @Test("Rule 3: enabled and blocking passes")
    func crossAccountLeakRequired() {
        let doc = document(grants: [], guards: Guards(crossAccountLeak: .crossAccountLeakRequired))
        #expect(RulesSemanticValidator.issues(in: doc).isEmpty)
    }

    @Test("Issue descriptions carry the pointer")
    func issueDescription() {
        let issue = RulesSemanticValidator.issues(in: document(grants: [grant("work", .l3)])).first
        #expect(issue?.description.hasPrefix("/autonomy/0: autonomy level L3") == true)
    }
}
