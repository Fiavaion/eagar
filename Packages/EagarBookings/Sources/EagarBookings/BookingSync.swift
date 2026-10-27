import EagarCalendar
import EagarCore
import EagarFeeds
import EagarStore
import Foundation

/// Errors from a refresh.
public enum BookingSyncError: Error, Equatable, Sendable, LogSafe {
    /// The source has no ``FeedSourceRecord``; register it first.
    case notRegistered
    case source(BookingSourceError)
    case store(StoreError)

    public var logDescription: String {
        switch self {
        case .notRegistered: "notRegistered"
        case let .source(error): "source(\(error.logDescription))"
        case let .store(error): "store(\(error.logDescription))"
        }
    }
}

/// What a refresh did. Counts only.
public struct BookingRefreshOutcome: Sendable, Hashable {
    public let path: BookingFetchPath
    public let changed: Bool
    public let upserted: Int
    public let deleted: Int
    public let deadlines: DeadlineReconcileCounts
}

/// Pulls a ``BookingSource`` into CollegeStore: bookings, their loan deadlines (FR-DL-01,
/// origin `booking`) and the source's cursor and health. Rules only; no model calls.
public struct BookingSync: Sendable {
    private let stores: EagarStores
    private let clock: any EagarClock
    private let reminderOffsetsMinutes: [Int]
    private let log = EagarLog(.feeds)

    /// - Parameter reminderOffsetsMinutes: return reminders for new loan deadlines (FR-BOOK-03).
    public init(stores: EagarStores, clock: any EagarClock = SystemClock(), reminderOffsetsMinutes: [Int] = LoanReminders.defaultOffsetsMinutes) {
        self.stores = stores
        self.clock = clock
        self.reminderOffsetsMinutes = reminderOffsetsMinutes
    }

    /// Fetches changes and applies them. On failure the source's health is recorded (so
    /// Settings can show "token revoked" and the like) and the error is rethrown.
    @discardableResult
    public func refresh(_ source: some BookingSource) async throws(BookingSyncError) -> BookingRefreshOutcome {
        let registry = FeedSourceRegistry(stores: stores)
        let now = clock.now()
        let loaded: FeedSourceState?
        do {
            loaded = try await registry.state(of: source.sourceID)
        } catch {
            throw .store(error)
        }
        guard var state = loaded else { throw .notRegistered }
        state.lastAttemptAt = now
        let cursor = BookingCursor(etag: state.etag, since: state.cursor, fallbackETag: state.fallbackETag)

        let changes: BookingChanges
        do {
            changes = try await source.fetchChanges(since: cursor)
        } catch {
            log.notice("booking refresh failed: \(error)")
            state.health = error.health
            try? await registry.save(state)
            throw .source(error)
        }

        let outcome: BookingRefreshOutcome
        let next: BookingCursor
        do {
            switch changes {
            case let .unchanged(unchangedCursor, path):
                next = unchangedCursor
                outcome = BookingRefreshOutcome(path: path, changed: false, upserted: 0, deleted: 0, deadlines: DeadlineReconcileCounts())
            case let .incremental(upserts, deletedIDs, newCursor):
                next = newCursor
                outcome = try await apply(upserts, deletedIDs: deletedIDs, replaceAll: false, path: .json, source: source.sourceID, now: now)
            case let .snapshot(bookings, newCursor, path):
                next = newCursor
                outcome = try await apply(bookings, deletedIDs: [], replaceAll: true, path: path, source: source.sourceID, now: now)
            }
        } catch {
            state.health = .failing
            try? await registry.save(state)
            throw .store(error)
        }

        state.etag = next.etag
        state.cursor = next.since
        state.fallbackETag = next.fallbackETag
        state.health = .ok
        state.lastSuccessAt = now
        do {
            try await registry.save(state)
        } catch {
            throw .store(error)
        }
        log.info("booking refresh via \(outcome.path): \(outcome.upserted) upserted, \(outcome.deleted) deleted")
        return outcome
    }

    /// Fetches the admin summary (FR-BOOK-06) and records whether the token has admin scope.
    public func refreshAdminSummary(_ source: some BookingSource) async throws(BookingSyncError) -> AdminSummary? {
        let registry = FeedSourceRegistry(stores: stores)
        let summary: AdminSummary?
        do {
            summary = try await source.adminSummary()
        } catch {
            if error == .unauthorised || error == .revoked, var state = try? await registry.state(of: source.sourceID) {
                state.health = error.health
                try? await registry.save(state)
            }
            throw .source(error)
        }
        do {
            if var state = try await registry.state(of: source.sourceID), state.hasAdminScope != (summary != nil) {
                state.hasAdminScope = summary != nil
                try await registry.save(state)
            }
        } catch {
            throw .store(error)
        }
        return summary
    }

    /// Deletes a source's bookings, deadlines and record. The caller deletes its secrets
    /// with ``CDBookingSecrets/delete(for:)``.
    public func disconnect(_ source: SourceID) async throws(StoreError) {
        try await BookingRepository(stores: stores).removeAll(source: source)
        _ = try await FeedDeadlineReconciler(stores: stores).removeAll(origin: .booking, source: source)
        try await FeedSourceRegistry(stores: stores).remove(source)
    }

    private func apply(
        _ records: [BookingRecord], deletedIDs: [String], replaceAll: Bool, path: BookingFetchPath, source: SourceID, now: Date
    ) async throws(StoreError) -> BookingRefreshOutcome {
        let counts = try await BookingRepository(stores: stores).apply(records, deletedIDs: deletedIDs, replaceAll: replaceAll, source: source, now: now)
        let reconciler = FeedDeadlineReconciler(stores: stores)
        let deadlines = records.compactMap { LoanReminders.deadline(for: $0, source: source, offsetsMinutes: reminderOffsetsMinutes) }
        var deadlineCounts = try await reconciler.upsert(deadlines, replacingAllFrom: replaceAll ? (.booking, source) : nil, now: now)
        if !replaceAll {
            let ids = deletedIDs.map { FeedDeadline.deadlineID(origin: .booking, sourceID: source, externalID: $0) }
            deadlineCounts.deleted += try await reconciler.remove(ids: ids)
        }
        return BookingRefreshOutcome(path: path, changed: true, upserted: counts.upserted, deleted: counts.deleted, deadlines: deadlineCounts)
    }
}
