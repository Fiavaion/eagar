import CryptoKit
import EagarCalendar
import EagarCore
import EagarStore
import Foundation
import SwiftData

/// Deterministic identifiers for records derived from feed items.
public enum StableID {
    /// A UUID derived from SHA-256 of the parts (RFC 9562 version 8 layout). The same parts
    /// always give the same UUID, so a feed item maps to one deadline on every refresh.
    public static func uuid(_ parts: String...) -> UUID {
        let digest = SHA256.hash(data: Data(parts.joined(separator: "\u{1F}").utf8))
        var bytes = Array(digest.prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x80
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

/// A deadline derived from a feed item (FR-DL-01, origins `booking` and `canvas`), as a value.
///
/// Its class comes from the taint rule over the item's class, so a deadline from a college
/// feed is college and lives in CollegeStore.
public struct FeedDeadline: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let title: String
    public let dueAt: Date
    public let isAllDay: Bool
    public let origin: DeadlineOrigin
    public let sourceID: SourceID
    public let dataClass: DataClass
    public let reminderOffsetsMinutes: [Int]
    /// The item is finished (loan returned, booking cancelled); its deadline is marked done.
    public let isClosed: Bool

    /// - Parameter externalID: the item's identifier in its feed (booking ID, Canvas UID).
    public init(
        origin: DeadlineOrigin, sourceID: SourceID, externalID: String, title: String, dueAt: Date, isAllDay: Bool,
        itemClass: DataClass, reminderOffsetsMinutes: [Int] = defaultDeadlineOffsetsMinutes, isClosed: Bool = false
    ) {
        id = Self.deadlineID(origin: origin, sourceID: sourceID, externalID: externalID)
        self.title = title
        self.dueAt = dueAt
        self.isAllDay = isAllDay
        self.origin = origin
        self.sourceID = sourceID
        dataClass = Taint.derive(.feedDeadline, from: [itemClass])
        self.reminderOffsetsMinutes = reminderOffsetsMinutes
        self.isClosed = isClosed
    }

    /// The deadline UUID for a feed item, stable across refreshes and devices.
    public static func deadlineID(origin: DeadlineOrigin, sourceID: SourceID, externalID: String) -> UUID {
        StableID.uuid("deadline", origin.rawValue, sourceID.rawValue.uuidString, externalID)
    }

    /// The snapshot the M1 notification planner takes. Closed items are `done`.
    public var snapshot: DeadlineSnapshot {
        DeadlineSnapshot(
            id: id, title: title, dueAt: dueAt, isAllDay: isAllDay, origin: origin,
            reminderOffsetsMinutes: reminderOffsetsMinutes, dataClass: dataClass, status: isClosed ? .done : .open
        )
    }
}

/// What a reconcile changed.
public struct DeadlineReconcileCounts: Sendable, Hashable {
    public var inserted = 0
    public var updated = 0
    public var closed = 0
    /// Done deadlines opened again because their item reopened in the feed.
    public var reopened = 0
    public var deleted = 0

    public init() {}
}

/// Upserts feed deadlines as M1 ``Deadline`` records, keyed by their stable UUID.
///
/// Mark's own changes survive a refresh: status, snooze (unless the due time moves), reminder
/// offsets and the reminder mirror are never overwritten from the feed.
public struct FeedDeadlineReconciler: Sendable {
    let stores: EagarStores

    public init(stores: EagarStores) {
        self.stores = stores
    }

    /// Upserts `deadlines`. A closed item marks its deadline done, and creates none if it had
    /// none. With `replacingAllFrom` set, deadlines of that origin and source
    /// that are not in `deadlines` are deleted (the feed was read in full).
    ///
    /// - Parameter reopening: deadlines whose item the feed itself moved from closed back to
    ///   open (a wrongly scanned return corrected to checked out). Those are opened again if
    ///   done, so their reminders fire. A deadline Mark marked done while the feed still showed
    ///   the item open is never in this set, so his "done" is kept.
    public func upsert(
        _ deadlines: [FeedDeadline], replacingAllFrom scope: (origin: DeadlineOrigin, source: SourceID)? = nil,
        reopening: Set<UUID> = [], now: Date
    ) async throws(StoreError) -> DeadlineReconcileCounts {
        var counts = DeadlineReconcileCounts()
        let byStore = Dictionary(grouping: deadlines) { StoreKind.placement(for: $0.dataClass) }
        for store in [stores.college, stores.personal] {
            let items = byStore[store.kind] ?? []
            let originRaw = scope?.origin.rawValue
            let sourceUUID = scope?.source.rawValue
            let keep = Set(deadlines.map(\.id))
            let result = try await run(in: store) { context in
                var counts = DeadlineReconcileCounts()
                for item in items {
                    let id = item.id
                    let existing = try context.fetch(FetchDescriptor<Deadline>(predicate: #Predicate { $0.deadlineUUID == id }))
                    if let deadline = existing.first {
                        existing.dropFirst().forEach(context.delete)
                        if Self.apply(item, to: deadline, now: now) { counts.updated += 1 }
                        if item.isClosed, deadline.status == .open {
                            deadline.markDone(at: now)
                            counts.closed += 1
                        } else if !item.isClosed, deadline.status == .done, reopening.contains(item.id) {
                            deadline.reopen()
                            counts.reopened += 1
                        }
                    } else if !item.isClosed {
                        // A closed item with no deadline yet (a loan already returned) adds nothing.
                        let deadline = Deadline(
                            deadlineUUID: item.id, title: item.title, dueAt: item.dueAt, isAllDay: item.isAllDay,
                            origin: item.origin, reminderOffsetsMinutes: item.reminderOffsetsMinutes,
                            dataClass: item.dataClass, sourceID: item.sourceID, createdAt: now
                        )
                        context.insert(deadline)
                        counts.inserted += 1
                    }
                }
                if let originRaw, let sourceUUID {
                    let scoped = try context.fetch(FetchDescriptor<Deadline>(
                        predicate: #Predicate { $0.originRaw == originRaw && $0.sourceUUID == sourceUUID }
                    ))
                    for deadline in scoped where !keep.contains(deadline.deadlineUUID) {
                        context.delete(deadline)
                        counts.deleted += 1
                    }
                }
                return counts
            }
            counts.inserted += result.inserted
            counts.updated += result.updated
            counts.closed += result.closed
            counts.reopened += result.reopened
            counts.deleted += result.deleted
        }
        return counts
    }

    /// Deletes the deadlines with these UUIDs (items the feed reported deleted).
    public func remove(ids: [UUID]) async throws(StoreError) -> Int {
        guard !ids.isEmpty else { return 0 }
        let wanted = Set(ids)
        var deleted = 0
        for store in [stores.college, stores.personal] {
            deleted += try await run(in: store) { context in
                var count = 0
                for id in wanted {
                    for deadline in try context.fetch(FetchDescriptor<Deadline>(predicate: #Predicate { $0.deadlineUUID == id })) {
                        context.delete(deadline)
                        count += 1
                    }
                }
                return count
            }
        }
        return deleted
    }

    /// Deletes every deadline of `origin` from `source` (the source was disconnected).
    public func removeAll(origin: DeadlineOrigin, source: SourceID) async throws(StoreError) -> Int {
        let originRaw = origin.rawValue
        let sourceUUID: UUID? = source.rawValue
        var deleted = 0
        for store in [stores.college, stores.personal] {
            deleted += try await run(in: store) { context in
                let rows = try context.fetch(FetchDescriptor<Deadline>(
                    predicate: #Predicate { $0.originRaw == originRaw && $0.sourceUUID == sourceUUID }
                ))
                rows.forEach(context.delete)
                return rows.count
            }
        }
        return deleted
    }

    /// Copies feed-owned fields. Returns whether anything changed.
    static func apply(_ item: FeedDeadline, to deadline: Deadline, now: Date) -> Bool {
        var changed = false
        if deadline.title != item.title { deadline.title = item.title; changed = true }
        if deadline.isAllDay != item.isAllDay { deadline.isAllDay = item.isAllDay; changed = true }
        if deadline.dueAt != item.dueAt { deadline.reschedule(to: item.dueAt); changed = true }
        return changed
    }
}
