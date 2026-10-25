import EagarCore
import EagarStore
import Foundation
import SwiftData

/// A consent to send one source's data, for one purpose, to one tier (BD-20, FR-PRIV-07).
@Model
public final class ConsentRecord: Classified {
    var consentUUID: UUID = UUID()
    /// `nil` covers user-authored content with no source.
    var sourceUUID: UUID?
    var purposeRaw: String = ""
    var tierRaw: String = Tier.anthropicCloud.rawValue
    var grantedAt: Date = Date.distantPast
    var revokedAt: Date?
    /// Version of the consent text Mark agreed to.
    var textVersion: Int = 0

    init(sourceID: SourceID?, purpose: AIPurpose, tier: Tier, grantedAt: Date, textVersion: Int) {
        sourceUUID = sourceID?.rawValue
        purposeRaw = purpose.rawValue
        tierRaw = tier.rawValue
        self.grantedAt = grantedAt
        self.textVersion = textVersion
    }

    /// Consent records describe Mark's choices about personal data; never college.
    public var dataClass: DataClass { .personal }
    public var sourceID: SourceID? { sourceUUID.map(SourceID.init) }
}

/// The lookup key for an active consent.
public struct ConsentKey: Hashable, Sendable {
    public var sourceID: SourceID?
    public var purpose: AIPurpose
    public var tier: Tier

    public init(sourceID: SourceID?, purpose: AIPurpose, tier: Tier) {
        self.sourceID = sourceID
        self.purpose = purpose
        self.tier = tier
    }
}

/// Grants, revokes and lists consents, persisted in PersonalStore.
public final class ConsentRegistry: Sendable {
    private let store: ClassifiedStore
    private let clock: any EagarClock

    public init(stores: EagarStores, clock: any EagarClock = SystemClock()) {
        store = stores.personal
        self.clock = clock
    }

    /// Records a consent and returns its ID (referenced by ledger entries).
    @discardableResult
    public func grant(_ key: ConsentKey, textVersion: Int) async throws(StoreError) -> UUID {
        let record = ConsentRecord(
            sourceID: key.sourceID, purpose: key.purpose, tier: key.tier, grantedAt: clock.now(), textVersion: textVersion
        )
        let id = record.consentUUID
        try await store.insert(record)
        return id
    }

    /// Revokes every active consent matching `key`. Takes effect before the next call, because
    /// the router reads consents fresh for every request.
    public func revoke(_ key: ConsentKey) async throws {
        let now = clock.now()
        let source = key.sourceID?.rawValue
        let purpose = key.purpose.rawValue
        let tier = key.tier.rawValue
        try await store.perform { context in
            let matches = try context.fetch(FetchDescriptor<ConsentRecord>(predicate: #Predicate {
                $0.sourceUUID == source && $0.purposeRaw == purpose && $0.tierRaw == tier && $0.revokedAt == nil
            }))
            matches.forEach { $0.revokedAt = now }
        }
    }

    /// Active consents, keyed for the router.
    public func active() async throws(StoreError) -> [ConsentKey: UUID] {
        let rows = try await store.fetch(FetchDescriptor<ConsentRecord>(predicate: #Predicate { $0.revokedAt == nil })) { record in
            (record.sourceUUID, record.purposeRaw, record.tierRaw, record.consentUUID)
        }
        var result: [ConsentKey: UUID] = [:]
        for (source, purposeRaw, tierRaw, id) in rows {
            guard let purpose = AIPurpose(rawValue: purposeRaw), let tier = Tier(rawValue: tierRaw) else { continue }
            result[ConsentKey(sourceID: source.map(SourceID.init), purpose: purpose, tier: tier)] = id
        }
        return result
    }
}
