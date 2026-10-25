import EagarCore
import EagarSecurity
import EagarStore
import Foundation
import SwiftData

/// The privacy ledger (BD-19, FR-PRIV-01…08), persisted in the two stores.
///
/// Entries derived from college data live in CollegeStore and never hold a payload; all other
/// entries live in PersonalStore. Only entries for calls that leave Mark's devices keep the
/// exact payload bytes.
public final class PrivacyLedger: PrivacyLedgerWriting {
    private let stores: EagarStores
    private let authenticator: any DeviceOwnerAuthenticating
    private let clock: any EagarClock
    private let log = EagarLog(.ledger)

    public init(stores: EagarStores, authenticator: any DeviceOwnerAuthenticating, clock: any EagarClock = SystemClock()) {
        self.stores = stores
        self.authenticator = authenticator
        self.clock = clock
    }

    // MARK: Writing

    public func record(_ draft: LedgerDraft) async throws(LedgerError) -> LedgerEntryID {
        let dataClass = Taint.derive(.ledgerEntry, from: draft.payloadClasses)
        let keepsPayload = dataClass != .college && (draft.tier?.leavesOwnerDevices ?? false)
        let outcome: LedgerOutcome = switch draft.kind {
        case .modelCall, .keyTest: .pending
        case .blocked: .blocked
        case .purge, .mcpCall, .pushRegistration, .killSwitch, .erase: .notApplicable
        }
        let id = UUID()
        let entry = LedgerEntry(
            id: id, at: clock.now(), dataClass: dataClass, draft: draft,
            payload: keepsPayload ? draft.payload : nil, outcome: outcome
        )
        do {
            try await stores.insert(entry)
        } catch {
            log.fault("ledger write failed: \(error)")
            throw .writeFailed
        }
        return LedgerEntryID(rawValue: id, store: StoreKind.placement(for: dataClass))
    }

    public func complete(_ id: LedgerEntryID, with completion: LedgerCompletion) async throws(LedgerError) {
        let store = id.store == .college ? stores.college : stores.personal
        let uuid = id.rawValue
        let result: Result<Void, LedgerError>
        do {
            result = try await store.perform { context in
                var descriptor = FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.entryUUID == uuid })
                descriptor.fetchLimit = 1
                guard let entry = try context.fetch(descriptor).first else { return .failure(.notFound) }
                guard entry.outcome == .pending else { return .failure(.alreadyCompleted) }
                entry.outcomeRaw = completion.outcome.rawValue
                entry.inputTokens = completion.inputTokens
                entry.outputTokens = completion.outputTokens
                entry.cacheReadTokens = completion.cacheReadTokens
                entry.cacheWriteTokens = completion.cacheWriteTokens
                entry.costMicroUSD = completion.costMicroUSD
                entry.durationMilliseconds = completion.duration.map { Int($0 / .milliseconds(1)) }
                return .success(())
            }
        } catch {
            log.error("ledger completion failed for \(id)")
            throw .writeFailed
        }
        try result.get()
    }

    // MARK: Reading

    /// Entries from both stores, newest first, optionally limited to a date range.
    public func records(from start: Date? = nil, to end: Date? = nil) async throws(LedgerError) -> [LedgerRecord] {
        let lower = start ?? .distantPast
        let upper = end ?? .distantFuture
        var all: [LedgerRecord] = []
        for store in [stores.personal, stores.college] {
            let kind = store.kind
            let descriptor = FetchDescriptor<LedgerEntry>(
                predicate: #Predicate { $0.at >= lower && $0.at <= upper },
                sortBy: [SortDescriptor(\.at, order: .reverse)]
            )
            do {
                all += try await store.fetch(descriptor) { LedgerRecord($0, store: kind) }
            } catch {
                throw .readFailed
            }
        }
        return all.sorted { $0.at > $1.at }
    }

    public func summary() async throws(LedgerError) -> LedgerSummary {
        let all = try await records()
        return LedgerSummary(
            cloudCallsWithCollegeContent: all.filter(\.isCloudCallWithCollegeContent).count,
            blockedAttempts: all.filter { $0.kind == .blocked }.count,
            offDeviceCalls: all.filter { ($0.tier?.leavesOwnerDevices ?? false) && $0.outcome != .blocked }.count,
            totalCostMicroUSD: all.compactMap(\.costMicroUSD).reduce(0, +)
        )
    }

    // MARK: Erasure

    /// Deletes entries older than `cutoff` after device-owner authentication, then records the
    /// erasure itself (FR-PRIV-08). This is the only way entries are ever removed.
    public func erase(before cutoff: Date, reason: String) async throws(LedgerError) -> Int {
        do {
            _ = try await authenticator.authenticate(reason: reason)
        } catch {
            log.notice("ledger erase refused: \(error)")
            throw .authenticationFailed
        }
        var removed = 0
        for store in [stores.personal, stores.college] {
            do {
                removed += try await store.perform { context in
                    let old = try context.fetch(FetchDescriptor<LedgerEntry>(predicate: #Predicate { $0.at < cutoff }))
                    old.forEach(context.delete)
                    return old.count
                }
            } catch {
                throw .writeFailed
            }
        }
        _ = try await record(LedgerDraft(kind: .erase, purpose: "ledgerErase", payloadClasses: [], detail: removed))
        log.notice("ledger erased \(removed) entries")
        return removed
    }
}
