import EagarCore
import EagarSecurity
import EagarStore
import Foundation
import Testing
@testable import EagarLedger

struct FixedClock: EagarClock {
    let date: Date
    func now() -> Date { date }
}

struct StubAuthenticator: DeviceOwnerAuthenticating {
    let succeeds: Bool
    func authenticate(reason: String) async throws(SecurityError) -> AuthenticationProof {
        guard succeeds else { throw .authenticationCancelled }
        return AuthenticationProof(at: Date(), method: .passcode)
    }
}

private func makeLedger(authenticates: Bool = true, at date: Date = Date(timeIntervalSince1970: 1_800_000_000)) throws -> PrivacyLedger {
    let stores = try EagarStores(location: .inMemory, models: [LedgerEntry.self])
    return PrivacyLedger(stores: stores, authenticator: StubAuthenticator(succeeds: authenticates), clock: FixedClock(date: date))
}

private let payload = Data(#"{"model":"claude-haiku-5-5","messages":[]}"#.utf8)

struct PrivacyLedgerTests {
    @Test func personalCloudCallKeepsExactPayloadInPersonalStore() async throws {
        let ledger = try makeLedger()
        let id = try await ledger.record(LedgerDraft(
            kind: .modelCall, purpose: "briefPhrase", payloadClasses: [.personal, .publicContent],
            tier: .anthropicCloud, destination: "anthropic", region: "global", modelID: "claude-haiku-5-5",
            payload: payload, inputCount: 2
        ))
        #expect(id.store == .personal)
        let record = try #require(try await ledger.records().first)
        #expect(record.payload == String(decoding: payload, as: UTF8.self))
        #expect(record.dataClass == .personal)
        #expect(record.payloadClasses == [.publicContent, .personal])
        #expect(record.outcome == .pending)
    }

    /// FR-PRIV-03: anything involving college data is metadata-only and stays in CollegeStore.
    @Test func collegeEntriesNeverKeepPayloadAndLiveInCollegeStore() async throws {
        let ledger = try makeLedger()
        let id = try await ledger.record(LedgerDraft(
            kind: .modelCall, purpose: "triage", payloadClasses: [.college, .personal],
            tier: .selfHostedInstitutional, destination: "meitheal", payload: payload, inputCount: 2
        ))
        #expect(id.store == .college)
        let record = try #require(try await ledger.records().first)
        #expect(record.payload == nil)
        #expect(record.dataClass == .college)
    }

    @Test func onDeviceCallsAreMetadataOnly() async throws {
        let ledger = try makeLedger()
        _ = try await ledger.record(LedgerDraft(
            kind: .modelCall, purpose: "triage", payloadClasses: [.personal], tier: .onDevice, payload: payload
        ))
        #expect(try await ledger.records().first?.payload == nil)
    }

    @Test func completionIsWrittenOnceOnly() async throws {
        let ledger = try makeLedger()
        let id = try await ledger.record(LedgerDraft(
            kind: .modelCall, purpose: "x", payloadClasses: [.publicContent], tier: .anthropicCloud, payload: payload
        ))
        let done = LedgerCompletion(outcome: .succeeded, inputTokens: 10, outputTokens: 5, costMicroUSD: 4, duration: .milliseconds(250))
        try await ledger.complete(id, with: done)
        await #expect(throws: LedgerError.alreadyCompleted) { try await ledger.complete(id, with: done) }
        let record = try #require(try await ledger.records().first)
        #expect(record.outcome == .succeeded)
        #expect(record.inputTokens == 10 && record.outputTokens == 5 && record.costMicroUSD == 4)
        #expect(record.durationMilliseconds == 250)
    }

    @Test func completingUnknownEntryFails() async throws {
        let ledger = try makeLedger()
        await #expect(throws: LedgerError.notFound) {
            try await ledger.complete(LedgerEntryID(rawValue: UUID(), store: .personal), with: LedgerCompletion(outcome: .failed))
        }
    }

    @Test func blockedEntriesCountedInSummary() async throws {
        let ledger = try makeLedger()
        _ = try await ledger.record(LedgerDraft(
            kind: .blocked, purpose: "draftReply", payloadClasses: [.college], tier: .anthropicCloud,
            payload: payload, detail: DataClass.college
        ))
        let id = try await ledger.record(LedgerDraft(
            kind: .modelCall, purpose: "x", payloadClasses: [.personal], tier: .anthropicCloud, payload: payload
        ))
        try await ledger.complete(id, with: LedgerCompletion(outcome: .succeeded, costMicroUSD: 120))

        let summary = try await ledger.summary()
        #expect(summary == LedgerSummary(cloudCallsWithCollegeContent: 0, blockedAttempts: 1, offDeviceCalls: 1, totalCostMicroUSD: 120))
        let blocked = try #require(try await ledger.records().first { $0.kind == .blocked })
        #expect(blocked.store == .college)
        #expect(blocked.payload == nil)
        #expect(blocked.outcome == .blocked)
        #expect(blocked.detail == "college")
    }

    @Test func eraseRequiresAuthentication() async throws {
        let ledger = try makeLedger(authenticates: false)
        _ = try await ledger.record(LedgerDraft(kind: .modelCall, purpose: "x", payloadClasses: [.personal], tier: .onDevice))
        await #expect(throws: LedgerError.authenticationFailed) {
            try await ledger.erase(before: .distantFuture, reason: "test")
        }
        #expect(try await ledger.records().count == 1)
    }

    @Test func eraseRemovesOldEntriesAndLedgersItself() async throws {
        let ledger = try makeLedger()
        _ = try await ledger.record(LedgerDraft(kind: .modelCall, purpose: "x", payloadClasses: [.personal], tier: .onDevice))
        _ = try await ledger.record(LedgerDraft(kind: .blocked, purpose: "y", payloadClasses: [.college]))
        let removed = try await ledger.erase(before: .distantFuture, reason: "test")
        #expect(removed == 2)
        let remaining = try await ledger.records()
        #expect(remaining.map(\.kind) == [.erase])
        #expect(remaining.first?.detail == "2")
    }

    @Test func earlierErasuresSurviveLaterErasures() async throws {
        let ledger = try makeLedger()
        _ = try await ledger.record(LedgerDraft(kind: .modelCall, purpose: "x", payloadClasses: [.personal], tier: .onDevice))
        #expect(try await ledger.erase(before: .distantFuture, reason: "first") == 1)
        #expect(try await ledger.erase(before: .distantFuture, reason: "second") == 0)
        let kinds = try await ledger.records().map(\.kind)
        #expect(kinds == [.erase, .erase])
    }

    @Test func exportOmitsPayloadsWhenAsked() async throws {
        let ledger = try makeLedger()
        _ = try await ledger.record(LedgerDraft(
            kind: .modelCall, purpose: "x", payloadClasses: [.personal], tier: .anthropicCloud, payload: payload
        ))
        let records = try await ledger.records()
        let date = Date(timeIntervalSince1970: 0)

        let withPayload = try LedgerExport.export(records, as: .json, includePayloads: true, exportedAt: date)
        let without = try LedgerExport.export(records, as: .json, includePayloads: false, exportedAt: date)
        #expect(String(decoding: withPayload, as: UTF8.self).contains("claude-haiku-5-5\\\",\\\"messages"))
        let stripped = String(decoding: without, as: UTF8.self)
        #expect(!stripped.contains("messages"))
        let json = try JSONSerialization.jsonObject(with: without) as! [String: Any]
        #expect(json["format"] as? String == "eagar-privacy-ledger")
        #expect(json["formatVersion"] as? String == "1.0")
        #expect(json["includesPayloads"] as? Bool == false)

        let csv = String(decoding: try LedgerExport.export(records, as: .csv, includePayloads: true, exportedAt: date), as: UTF8.self)
        let lines = csv.split(separator: "\n")
        #expect(lines.count == 3)
        #expect(lines[1] == Substring(LedgerExport.csvColumns.joined(separator: ",")))
        #expect(lines[2].hasSuffix(#""{""model"":""claude-haiku-5-5"",""messages"":[]}""#))
    }

    @Test func csvEscaping() {
        #expect(LedgerExport.escape("plain") == "plain")
        #expect(LedgerExport.escape("a,b") == "\"a,b\"")
        #expect(LedgerExport.escape("say \"hi\"") == "\"say \"\"hi\"\"\"")
        #expect(LedgerExport.escape("line\nbreak") == "\"line\nbreak\"")
    }
}
