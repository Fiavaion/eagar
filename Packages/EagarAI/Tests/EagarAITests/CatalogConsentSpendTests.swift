import EagarAITestSupport
import EagarCore
import EagarLedger
import EagarStore
import Foundation
import Testing
@testable import EagarAI

struct ModelCatalogTests {
    @Test func bundledCatalogMatchesVerifiedSeeds() throws {
        #expect(catalog.verifiedOn == "2026-10-25")
        #expect(catalog.defaults[.light] == ModelID("claude-haiku-5-5"))
        #expect(catalog.defaults[.standard] == ModelID("claude-sonnet-5-5"))
        #expect(catalog.offeredModels.map(\.id.rawValue) == ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"])
        #expect(catalog.model(ModelID("claude-fable-5-1"))?.offered == false)
        let haiku = try #require(catalog.model(ModelID("claude-haiku-5-5")))
        #expect(haiku.pricing.first?.inputPerMTok == Decimal(string: "0.10"))
        #expect(haiku.pricing.first?.outputPerMTok == Decimal(string: "0.50"))
        #expect(catalog.model(ModelID("claude-opus-5-5"))?.pricing.first?.outputPerMTok == 20)
    }

    @Test func costUsesThePromptSizeTier() {
        let haiku = ModelID("claude-haiku-5-5")
        // 1M input + 1M output under the 100K-prompt tier is impossible; use proportional counts.
        #expect(catalog.costMicroUSD(model: haiku, usage: LLMUsage(inputTokens: 100_000, outputTokens: 1_000)) == Int64(10_000 + 500))
        #expect(catalog.costMicroUSD(model: haiku, usage: LLMUsage(inputTokens: 100_001, outputTokens: 1_000)) == Int64(50_001 + 2_500))
        // The tier is chosen on total prompt size, including cache reads.
        #expect(catalog.costMicroUSD(model: haiku, usage: LLMUsage(inputTokens: 1, cacheReadTokens: 100_000)) == Int64(5_001)) // 0.5 + 5,000 µ$, rounded half up
        let sonnet = ModelID("claude-sonnet-5-5")
        #expect(catalog.costMicroUSD(model: sonnet, usage: LLMUsage(inputTokens: 1_000, outputTokens: 100, cacheReadTokens: 10_000, cacheWriteTokens: 1_000)) == Int64(2_000 + 1_000 + 2_000 + 2_500))
        #expect(catalog.costMicroUSD(model: ModelID("unknown"), usage: LLMUsage(inputTokens: 1)) == nil)
    }
}

struct ConsentRegistryTests {
    @Test func grantRevokeAndActive() async throws {
        let stores = try EagarStores(location: .inMemory, models: [ConsentRecord.self])
        let registry = ConsentRegistry(stores: stores)
        let source = SourceID()
        let key = ConsentKey(sourceID: source, purpose: .draftReply, tier: .anthropicCloud)
        let id = try await registry.grant(key, textVersion: 1)
        try await registry.grant(ConsentKey(sourceID: nil, purpose: .briefPhrase, tier: .anthropicCloud), textVersion: 1)
        var active = try await registry.active()
        #expect(active[key] == id)
        #expect(active.count == 2)

        try await registry.revoke(key)
        active = try await registry.active()
        #expect(active[key] == nil)
        #expect(active.count == 1)
    }

    /// FR-PRIV-07: revocation takes effect before the next call.
    @Test func revocationStopsTheNextCall() async throws {
        let stores = try EagarStores(location: .inMemory, models: [ConsentRecord.self])
        let registry = ConsentRegistry(stores: stores)
        let source = SourceID()
        let key = ConsentKey(sourceID: source, purpose: .draftReply, tier: .anthropicCloud)
        try await registry.grant(key, textVersion: 1)

        struct LivePolicy: PolicySource {
            let registry: ConsentRegistry
            let source: SourceID
            func snapshot() async throws -> PolicySnapshot {
                PolicySnapshot(sourceModes: [source: .cloudAllowed], consents: try await registry.active())
            }
        }
        let cloud = RecordingProvider(.anthropicCloud(region: "global"))
        let router = AIRouter(providers: [cloud], ledger: InMemoryLedger(), policy: LivePolicy(registry: registry, source: source), catalog: catalog)
        let request = AIRequest(
            purpose: .draftReply,
            inputs: [ClassifiedPayload("body", dataClass: .personal, sourceID: source, kind: .rawBody)],
            preferredTier: .anthropicCloud
        )
        _ = try await router.run(request)
        try await registry.revoke(key)
        await #expect(throws: AIError.boundaryViolation(requested: .anthropicCloud, reason: .consentRequired)) {
            try await router.run(request)
        }
        #expect(cloud.recordedCalls.count == 1)
    }

    @Test func consentRecordsAreNeverCollege() {
        let record = ConsentRecord(sourceID: nil, purpose: .triage, tier: .anthropicCloud, grantedAt: Date(), textVersion: 1)
        #expect(record.dataClass == .personal)
    }
}

struct SpendMeterTests {
    @Test func reportAndCap() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 12))!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        let lastMonth = calendar.date(byAdding: .month, value: -1, to: now)!

        let stores = try EagarStores(location: .inMemory, models: [LedgerEntry.self])
        var records: [LedgerRecord] = []
        for (date, purpose, cost) in [(now, "briefPhrase", Int64(300)), (yesterday, "triage", 200), (lastMonth, "triage", 1_000)] {
            struct Clock: EagarClock { let date: Date; func now() -> Date { date } }
            let ledger = PrivacyLedger(stores: stores, authenticator: AllowAuth(), clock: Clock(date: date))
            let id = try await ledger.record(LedgerDraft(kind: .modelCall, purpose: purpose, payloadClasses: [.publicContent], tier: .anthropicCloud))
            try await ledger.complete(id, with: LedgerCompletion(outcome: .succeeded, costMicroUSD: cost))
            records = try await ledger.records()
        }

        let meter = SpendMeter(monthlyCapMicroUSD: 500, calendar: calendar)
        let report = meter.report(records, now: now)
        #expect(report.todayMicroUSD == 300)
        #expect(report.monthMicroUSD == 500)
        #expect(report.byPurposeMicroUSD == ["briefPhrase": 300, "triage": 200])
        #expect(report.byDayMicroUSD.count == 3)
        #expect(meter.isCapReached(records, now: now))
        #expect(!SpendMeter(monthlyCapMicroUSD: 501, calendar: calendar).isCapReached(records, now: now))
        #expect(!SpendMeter(calendar: calendar).isCapReached(records, now: now))
    }
}
