import EagarAITestSupport
import EagarCore
import EagarLedger
import Foundation
import Testing
@testable import EagarAI

let catalog = try! ModelCatalog.bundled()

func makeRouter(
    _ providers: [any LLMProvider],
    ledger: any PrivacyLedgerWriting = InMemoryLedger(),
    policy: PolicySnapshot = PolicySnapshot()
) -> AIRouter {
    AIRouter(providers: providers, ledger: ledger, policy: StaticPolicySource(policy), catalog: catalog)
}

private let cloudTiersForCollege: Set<Tier> = [.anthropicCloud, .applePCC, .selfHostedInstitutional]

struct AIRouterTests {
    /// B-1: college payload with every provider registered never reaches a cloud, PCC or Meitheal
    /// provider; an explicit cloud request is refused with exactly one blocked ledger entry.
    @Test(arguments: [Tier.anthropicCloud, .applePCC, .selfHostedInstitutional])
    func Boundary_B1_collegeNeverReachesCloud(requested: Tier) async throws {
        let providers = RecordingProvider.oneOfEach()
        let ledger = InMemoryLedger()
        let ncad = SourceID()
        let router = makeRouter(providers, ledger: ledger, policy: PolicySnapshot(
            sourceModes: [ncad: .localAI],
            consents: [ConsentKey(sourceID: ncad, purpose: .draftReply, tier: requested): UUID()] // consent cannot widen college
        ))
        let request = AIRequest(
            purpose: .draftReply,
            inputs: [ClassifiedPayload("college body", dataClass: .college, sourceID: ncad, kind: .rawBody)],
            preferredTier: requested
        )

        await #expect(throws: AIError.boundaryViolation(requested: requested, reason: .collegeBoundary)) {
            try await router.run(request)
        }
        for provider in providers {
            #expect(provider.recordedCalls.isEmpty, "\(provider.id) was called")
        }
        let blocked = ledger.entries.filter { $0.draft.kind == .blocked }
        #expect(blocked.count == 1)
        #expect(ledger.entries.count == 1)
        #expect(blocked.first?.draft.tier == requested)
        #expect(blocked.first?.draft.payload == nil)
        #expect(blocked.first?.id.store == .college)

        // Without a preference the same request is served locally.
        var unpinned = request
        unpinned.preferredTier = nil
        let response = try await router.run(unpinned)
        #expect(response.tier == .onDevice)
        let called = providers.filter { !$0.recordedCalls.isEmpty }.map(\.locality.tier)
        #expect(called == [.onDevice])
        #expect(Set(called).isDisjoint(with: cloudTiersForCollege))
    }

    /// B-2 through the router: one college input taints the call.
    @Test func Boundary_B2_mixedPayloadRoutedAsCollege() async throws {
        let providers = RecordingProvider.oneOfEach()
        let personalSource = SourceID()
        let router = makeRouter(providers, policy: PolicySnapshot(
            sourceModes: [personalSource: .cloudAllowed],
            consents: [ConsentKey(sourceID: personalSource, purpose: .briefPhrase, tier: .anthropicCloud): UUID()]
        ))
        let request = AIRequest(purpose: .briefPhrase, inputs: [
            ClassifiedPayload("personal", dataClass: .personal, sourceID: personalSource),
            ClassifiedPayload("public", dataClass: .publicContent),
            ClassifiedPayload("college", dataClass: .college),
        ])
        _ = try await router.run(request)
        let call = try #require(providers.flatMap(\.recordedCalls).first)
        #expect(call.effectiveClass == .college)
        #expect(!cloudTiersForCollege.contains(call.tier))
    }

    /// B-14 (router): a rulesOnly source makes zero provider calls, even with consent and a preference.
    @Test(arguments: [nil, Tier.onDevice, .anthropicCloud])
    func Boundary_B14_rulesOnlySourceMakesNoCalls(preferred: Tier?) async throws {
        let expected: AIError = preferred.map { .boundaryViolation(requested: $0, reason: .rulesOnlySource) } ?? .noPermittedProvider
        let providers = RecordingProvider.oneOfEach()
        let ledger = InMemoryLedger()
        let source = SourceID()
        let router = makeRouter(providers, ledger: ledger, policy: PolicySnapshot(
            sourceModes: [source: .rulesOnly],
            consents: [ConsentKey(sourceID: source, purpose: .triage, tier: .anthropicCloud): UUID()]
        ))
        let request = AIRequest(
            purpose: .triage,
            inputs: [ClassifiedPayload("subject line", dataClass: .personal, sourceID: source)],
            preferredTier: preferred
        )
        await #expect(throws: expected) { try await router.run(request) }
        #expect(providers.allSatisfy { $0.recordedCalls.isEmpty })
        #expect(ledger.entries.count == (preferred == nil ? 0 : 1))
        #expect(ledger.entries.allSatisfy { $0.draft.kind == .blocked && $0.draft.detail == "rulesOnlySource" })
    }

    /// The output schema reaches the provider, so it takes part in the taint rule (verify finding).
    @Test func Boundary_B1_collegeTextInOutputSchemaNeverReachesCloud() async throws {
        let providers = RecordingProvider.oneOfEach()
        let ledger = InMemoryLedger()
        let router = makeRouter(providers, ledger: ledger)
        let schema = JSONSchema(
            name: "Pick",
            json: Data(#"{"type":"string","enum":["COLLEGE-ONLY-VALUE"]}"#.utf8),
            dataClass: .college
        )
        let request = AIRequest(
            purpose: .extraction,
            inputs: [ClassifiedPayload("public", dataClass: .publicContent)],
            outputSchema: schema,
            preferredTier: .anthropicCloud
        )
        await #expect(throws: AIError.boundaryViolation(requested: .anthropicCloud, reason: .collegeBoundary)) {
            try await router.run(request)
        }
        #expect(providers.allSatisfy { $0.recordedCalls.isEmpty })
        #expect(ledger.entries.first?.draft.payloadClasses.contains(.college) == true)
    }

    /// The key test must reach Claude or fail; it never falls back to a local tier (verify finding).
    @Test func keyTestNeverFallsBack() async throws {
        let onDevice = RecordingProvider(.onDevice)
        let claude = RecordingProvider(.anthropicCloud(region: "global"), reachable: false)
        let outcome = await KeyTester.run(using: makeRouter([onDevice, claude]))
        #expect(outcome == .noKey)
        #expect(onDevice.recordedCalls.isEmpty)
    }

    @Test func rawBodyIsTheDefaultKind() {
        #expect(ClassifiedPayload("x", dataClass: .personal).kind == .rawBody)
    }

    @Test func unknownSourceFailsClosed() async throws {
        let providers = RecordingProvider.oneOfEach()
        let router = makeRouter(providers)
        let request = AIRequest(purpose: .triage, inputs: [ClassifiedPayload("x", dataClass: .publicContent, sourceID: SourceID())])
        await #expect(throws: AIError.noPermittedProvider) { try await router.run(request) }
        #expect(providers.allSatisfy { $0.recordedCalls.isEmpty })
    }

    /// FR-AI-04: personal raw bodies reach Claude only with consent; otherwise local.
    @Test func personalRawBodyNeedsConsentForClaude() async throws {
        let source = SourceID()
        let request = AIRequest(
            purpose: .draftReply,
            inputs: [ClassifiedPayload("personal body", dataClass: .personal, sourceID: source, kind: .rawBody)],
            preferredTier: .anthropicCloud
        )
        let providers = RecordingProvider.oneOfEach()
        let noConsent = makeRouter(providers, policy: PolicySnapshot(sourceModes: [source: .cloudAllowed]))
        await #expect(throws: AIError.boundaryViolation(requested: .anthropicCloud, reason: .consentRequired)) {
            try await noConsent.run(request)
        }
        var unpinned = request
        unpinned.preferredTier = nil
        #expect(try await noConsent.run(unpinned).tier == .onDevice)

        let consentID = UUID()
        let ledger = InMemoryLedger()
        let withConsent = makeRouter(providers, ledger: ledger, policy: PolicySnapshot(
            sourceModes: [source: .cloudAllowed],
            consents: [ConsentKey(sourceID: source, purpose: .draftReply, tier: .anthropicCloud): consentID]
        ))
        let response = try await withConsent.run(request)
        #expect(response.tier == .anthropicCloud)
        #expect(ledger.entries.last?.draft.consentID == consentID)
    }

    /// FR-PRIV-01: if the ledger cannot be written, nothing is sent.
    @Test func ledgerFailureSendsNothing() async throws {
        let providers = RecordingProvider.oneOfEach()
        let router = makeRouter(providers, ledger: InMemoryLedger(failWrites: true))
        let request = AIRequest(purpose: .briefPhrase, inputs: [ClassifiedPayload("x", dataClass: .publicContent)], preferredTier: .anthropicCloud)
        await #expect(throws: AIError.ledgerWriteFailed) { try await router.run(request) }
        #expect(providers.allSatisfy { $0.recordedCalls.isEmpty })
    }

    /// The ledger entry exists, with the exact payload, before the provider is called.
    @Test func ledgerEntryPrecedesDispatchWithExactPayload() async throws {
        let ledger = InMemoryLedger()
        let checked = RecordingProvider(.anthropicCloud(region: "global")) { call in
            let id = call.ledgerEntryID!
            #expect(ledger.contains(id))
            let entry = ledger.entries.first { $0.id == id }!
            #expect(entry.draft.payload == call.wirePayload)
            #expect(entry.completion == nil)
        }
        let router = makeRouter([checked], ledger: ledger)
        let response = try await router.run(AIRequest(purpose: .briefPhrase, inputs: [ClassifiedPayload("x", dataClass: .publicContent)]))
        #expect(checked.recordedCalls.count == 1)
        let entry = try #require(ledger.entries.first)
        #expect(entry.completion?.outcome == .succeeded)
        #expect(entry.completion?.inputTokens == 10)
        #expect(entry.draft.modelID == "claude-sonnet-5-5") // briefPhrase uses the standard default
        #expect(response.costMicroUSD == 40) // 10 × $2 + 2 × $10 per MTok
        #expect(response.ledgerEntryID == entry.id)
    }

    @Test func providerFailureIsLedgeredAsFailed() async throws {
        let ledger = InMemoryLedger()
        let failing = RecordingProvider(.anthropicCloud(region: "global"), failure: .provider(.http(status: 500)))
        let router = makeRouter([failing], ledger: ledger)
        await #expect(throws: AIError.provider(.http(status: 500))) {
            try await router.run(AIRequest(purpose: .triage, inputs: [ClassifiedPayload("x", dataClass: .publicContent)]))
        }
        #expect(ledger.entries.first?.completion?.outcome == .failed)
    }

    @Test func unreachablePreferredTierFallsBackWithinPolicy() async throws {
        let cloud = RecordingProvider(.anthropicCloud(region: "global"), reachable: false)
        let local = RecordingProvider(.macLocal)
        let router = makeRouter([cloud, local])
        let response = try await router.run(AIRequest(
            purpose: .triage, inputs: [ClassifiedPayload("x", dataClass: .publicContent)], preferredTier: .anthropicCloud
        ))
        #expect(response.tier == .macLocal)
    }

    @Test func fableIsNotOfferedByDefault() async throws {
        let router = makeRouter([RecordingProvider(.anthropicCloud(region: "global"))])
        await #expect(throws: AIError.modelNotOffered) {
            try await router.run(AIRequest(
                purpose: .planning, inputs: [ClassifiedPayload("x", dataClass: .publicContent)], model: ModelID("claude-fable-5-1")
            ))
        }
    }

    @Test func spendCapPausesClaude() async throws {
        let router = makeRouter(RecordingProvider.oneOfEach(), policy: PolicySnapshot(cloudPaused: true))
        await #expect(throws: AIError.boundaryViolation(requested: .anthropicCloud, reason: .cloudPaused)) {
            try await router.run(AIRequest(
                purpose: .planning, inputs: [ClassifiedPayload("x", dataClass: .publicContent)], preferredTier: .anthropicCloud
            ))
        }
    }

    /// The system prompt takes part in the taint rule.
    @Test func classifiedSystemPromptTaints() async throws {
        let providers = RecordingProvider.oneOfEach()
        let router = makeRouter(providers)
        let request = AIRequest(
            purpose: .briefPhrase,
            inputs: [ClassifiedPayload("x", dataClass: .publicContent)],
            system: ClassifiedPayload("college context", dataClass: .college),
            preferredTier: .anthropicCloud
        )
        await #expect(throws: AIError.boundaryViolation(requested: .anthropicCloud, reason: .collegeBoundary)) {
            try await router.run(request)
        }
        #expect(providers.allSatisfy { $0.recordedCalls.isEmpty })
    }
}
