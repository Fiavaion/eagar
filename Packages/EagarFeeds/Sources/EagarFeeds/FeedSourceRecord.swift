import EagarCore
import EagarStore
import Foundation
import SwiftData

/// A feed's health, shown in Settings so a failure is never silent (CLAUDE.md: visible error state).
public enum FeedHealth: String, Codable, Sendable, CaseIterable, LogSafe {
    /// Never fetched.
    case unknown
    /// The last fetch succeeded (including `304 Not Modified`).
    case ok
    /// The URL or token is missing from the Keychain; the source must be set up again.
    case notConfigured
    /// `401`: the token was rotated or revoked. Mark must paste a new one (Appendix E.2).
    case unauthorised
    /// `410 Gone`: the feed was revoked (Appendix E.2). Mark must create a new one.
    case revoked
    /// A transient failure (offline, timeout, server error, malformed body); retried next time.
    case failing

    public var logDescription: String { rawValue }

    /// Whether Mark must act before the feed can work again.
    public var needsAttention: Bool { self == .notConfigured || self == .unauthorised || self == .revoked }
}

/// A configured feed and its sync bookkeeping (PRD §7.3 `Source`, feed subset).
///
/// Lives in the store its class belongs in: CollegeStore for cdbooking and Canvas. Holds no
/// URL and no token; those are in the Keychain (invariant 6). CloudKit-compatible: every
/// attribute defaulted or optional, no unique constraints, no relationships. One record per
/// `sourceUUID` is enforced by ``FeedSourceRegistry``.
@Model
public final class FeedSourceRecord: Classified {
    public var sourceUUID: UUID = UUID()
    public var kindRaw: String = FeedKind.iCalendar.rawValue
    /// Mark's label for the source, e.g. "Bookings".
    public var displayName: String = ""
    public var dataClassRaw: String = DataClass.college.rawValue
    public var processingModeRaw: String = ProcessingMode.rulesOnly.rawValue
    /// `ETag` of the primary endpoint (cdbooking JSON, or the iCal feed for Canvas).
    public var etag: String?
    /// `ETag` of the fallback endpoint (the cdbooking iCal feed).
    public var fallbackETag: String?
    /// The server's incremental cursor (cdbooking `next_since`).
    public var cursor: String?
    public var healthRaw: String = FeedHealth.unknown.rawValue
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    /// Whether the token was last seen to have admin scope (cdbooking `admin:summary`).
    public var hasAdminScope: Bool = false
    public var createdAt: Date = Date.distantPast

    public init(source: FeedSource, displayName: String, createdAt: Date) {
        sourceUUID = source.id.rawValue
        kindRaw = source.kind.rawValue
        self.displayName = displayName
        dataClassRaw = source.dataClass.rawValue
        processingModeRaw = source.processingMode.rawValue
        self.createdAt = createdAt
    }

    /// Unknown raw values read as `college`.
    public var dataClass: DataClass { DataClass(rawValue: dataClassRaw) ?? .college }
    public var sourceID: SourceID? { SourceID(sourceUUID) }
    public var kind: FeedKind { FeedKind(rawValue: kindRaw) ?? .iCalendar }
    /// Unknown raw values read as `rulesOnly`, the most restrictive mode.
    public var processingMode: ProcessingMode { ProcessingMode(rawValue: processingModeRaw) ?? .rulesOnly }
    public var health: FeedHealth { FeedHealth(rawValue: healthRaw) ?? .unknown }

    public var state: FeedSourceState {
        FeedSourceState(
            source: FeedSource(id: SourceID(sourceUUID), kind: kind, dataClass: dataClass, processingMode: processingMode),
            displayName: displayName, etag: etag, fallbackETag: fallbackETag, cursor: cursor, health: health,
            lastAttemptAt: lastAttemptAt, lastSuccessAt: lastSuccessAt, hasAdminScope: hasAdminScope
        )
    }
}

/// A `Sendable` value copy of a ``FeedSourceRecord``.
public struct FeedSourceState: Sendable, Hashable {
    public let source: FeedSource
    public let displayName: String
    public var etag: String?
    public var fallbackETag: String?
    public var cursor: String?
    public var health: FeedHealth
    public var lastAttemptAt: Date?
    public var lastSuccessAt: Date?
    public var hasAdminScope: Bool

    public init(
        source: FeedSource, displayName: String, etag: String? = nil, fallbackETag: String? = nil, cursor: String? = nil,
        health: FeedHealth = .unknown, lastAttemptAt: Date? = nil, lastSuccessAt: Date? = nil, hasAdminScope: Bool = false
    ) {
        self.source = source
        self.displayName = displayName
        self.etag = etag
        self.fallbackETag = fallbackETag
        self.cursor = cursor
        self.health = health
        self.lastAttemptAt = lastAttemptAt
        self.lastSuccessAt = lastSuccessAt
        self.hasAdminScope = hasAdminScope
    }
}

/// Reads and writes ``FeedSourceRecord``s, one per source, in the store each class belongs in.
public struct FeedSourceRegistry: Sendable {
    let stores: EagarStores

    public init(stores: EagarStores) {
        self.stores = stores
    }

    /// Adds `source`, or updates its label if it exists.
    public func register(_ source: FeedSource, displayName: String, at date: Date) async throws(StoreError) {
        let id = source.id.rawValue
        let store = stores.store(for: source.dataClass)
        try await run(in: store) { context in
            let existing = try context.fetch(Self.descriptor(id))
            if let first = existing.first {
                first.displayName = displayName
                existing.dropFirst().forEach(context.delete)
            } else {
                context.insert(FeedSourceRecord(source: source, displayName: displayName, createdAt: date))
            }
        }
    }

    /// The source's state, from whichever store holds it.
    public func state(of source: SourceID) async throws(StoreError) -> FeedSourceState? {
        let id = source.rawValue
        for store in [stores.college, stores.personal] {
            if let state = try await store.fetch(Self.descriptor(id), map: \.state).first { return state }
        }
        return nil
    }

    /// Every registered feed.
    public func all() async throws(StoreError) -> [FeedSourceState] {
        var result: [FeedSourceState] = []
        for store in [stores.college, stores.personal] {
            result += try await store.fetch(FetchDescriptor<FeedSourceRecord>(), map: \.state)
        }
        return result
    }

    /// Writes the bookkeeping fields of `state` back to its record.
    public func save(_ state: FeedSourceState) async throws(StoreError) {
        let id = state.source.id.rawValue
        try await run(in: stores.store(for: state.source.dataClass)) { context in
            for record in try context.fetch(Self.descriptor(id)) {
                record.etag = state.etag
                record.fallbackETag = state.fallbackETag
                record.cursor = state.cursor
                record.healthRaw = state.health.rawValue
                record.lastAttemptAt = state.lastAttemptAt
                record.lastSuccessAt = state.lastSuccessAt
                record.hasAdminScope = state.hasAdminScope
            }
        }
    }

    /// Deletes the source's record. The caller also deletes its secrets and items.
    public func remove(_ source: SourceID) async throws(StoreError) {
        let id = source.rawValue
        for store in [stores.college, stores.personal] {
            try await run(in: store) { context in
                try context.fetch(Self.descriptor(id)).forEach(context.delete)
            }
        }
    }

    static func descriptor(_ id: UUID) -> FetchDescriptor<FeedSourceRecord> {
        FetchDescriptor<FeedSourceRecord>(predicate: #Predicate { $0.sourceUUID == id })
    }
}

/// Runs `body` in `store` with the class check, mapping any failure to a `StoreError`.
func run<R: Sendable>(in store: ClassifiedStore, _ body: @Sendable (ModelContext) throws -> R) async throws(StoreError) -> R {
    do {
        return try await store.perform(body)
    } catch let error as StoreError {
        throw error
    } catch {
        throw .saveFailed(store.kind)
    }
}
