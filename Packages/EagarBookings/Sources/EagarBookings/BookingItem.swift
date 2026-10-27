import EagarCore
import EagarStore
import Foundation
import SwiftData

/// A cdbooking booking or loan (PRD §7.3 `BookingItem`). Always `college` (BD-15), so it can
/// only be saved in CollegeStore, which is never synced and is excluded from backup.
///
/// CloudKit-compatible like every Eagar model: defaulted or optional attributes, no unique
/// constraints, no relationships. One record per (`sourceUUID`, `bookingID`) is enforced by
/// ``BookingRepository``. Holds no token and no feed URL (invariant 6).
@Model
public final class BookingItem: Classified {
    public var bookingID: String = ""
    public var sourceUUID: UUID = UUID()
    public var kindRaw: String = BookingKind.equipment.rawValue
    public var statusRaw: String = BookingStatus.unknown.rawValue
    public var title: String = ""
    public var itemNames: [String] = []
    public var department: String?
    public var location: String?
    public var startAt: Date?
    public var dueAt: Date?
    public var endAt: Date?
    public var returnedAt: Date?
    public var updatedAt: Date?
    public var bookingPageURL: String?
    public var extendPageURL: String?
    public var dataClassRaw: String = DataClass.college.rawValue
    public var fetchedAt: Date = Date.distantPast

    public init(_ record: BookingRecord, source: SourceID, fetchedAt: Date) {
        bookingID = record.id
        sourceUUID = source.rawValue
        apply(record, fetchedAt: fetchedAt)
    }

    /// Unknown raw values read as `college`.
    public var dataClass: DataClass { DataClass(rawValue: dataClassRaw) ?? .college }
    public var sourceID: SourceID? { SourceID(sourceUUID) }

    /// Copies every feed-owned field.
    public func apply(_ record: BookingRecord, fetchedAt: Date) {
        kindRaw = record.kind.rawValue
        statusRaw = record.status.rawValue
        title = record.title
        itemNames = record.itemNames
        department = record.department
        location = record.location
        startAt = record.start
        dueAt = record.due
        endAt = record.end
        returnedAt = record.returnedAt
        updatedAt = record.updatedAt
        bookingPageURL = record.pageURL?.absoluteString
        extendPageURL = record.extendURL?.absoluteString
        self.fetchedAt = fetchedAt
    }

    public var record: BookingRecord {
        BookingRecord(
            id: bookingID, kind: BookingKind(rawValue: kindRaw) ?? .equipment, status: BookingStatus(wire: statusRaw), title: title,
            itemNames: itemNames, department: department, location: location, start: startAt, due: dueAt, end: endAt,
            returnedAt: returnedAt, updatedAt: updatedAt, pageURL: bookingPageURL.flatMap(URL.init(string:)),
            extendURL: extendPageURL.flatMap(URL.init(string:))
        )
    }

    public var snapshot: BookingSnapshot {
        BookingSnapshot(sourceID: SourceID(sourceUUID), booking: record, dataClass: dataClass)
    }
}

/// Reads and upserts ``BookingItem``s in CollegeStore.
public struct BookingRepository: Sendable {
    let stores: EagarStores

    public init(stores: EagarStores) {
        self.stores = stores
    }

    /// Every stored booking, optionally for one source, ordered by due (or end, or start) time.
    public func all(source: SourceID? = nil) async throws(StoreError) -> [BookingSnapshot] {
        let descriptor: FetchDescriptor<BookingItem>
        if let id = source?.rawValue {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.sourceUUID == id })
        } else {
            descriptor = FetchDescriptor()
        }
        let rows = try await stores.college.fetch(descriptor) { $0.snapshot }
        return rows.sorted { Self.sortKey($0.booking) < Self.sortKey($1.booking) }
    }

    /// Active loans (checked out or overdue, with a due time), soonest first.
    public func activeLoans(source: SourceID? = nil) async throws(StoreError) -> [BookingSnapshot] {
        try await all(source: source).filter(\.booking.isActiveLoan)
    }

    private static func sortKey(_ record: BookingRecord) -> Date {
        record.due ?? record.end ?? record.start ?? .distantFuture
    }

    /// Upserts `records` for `source` by booking ID and deletes `deletedIDs`. With
    /// `replaceAll`, bookings of the source not in `records` are deleted too. Returns the IDs
    /// of stored bookings that were closed and are open again in `records`.
    func apply(
        _ records: [BookingRecord], deletedIDs: [String], replaceAll: Bool, source: SourceID, now: Date
    ) async throws(StoreError) -> (upserted: Int, deleted: Int, reopened: [String]) {
        let sourceUUID = source.rawValue
        do {
            return try await stores.college.perform { context in
                let existing = try context.fetch(FetchDescriptor<BookingItem>(predicate: #Predicate { $0.sourceUUID == sourceUUID }))
                var byID: [String: BookingItem] = [:]
                var deleted = 0
                var reopened: [String] = []
                for item in existing {
                    if byID[item.bookingID] == nil {
                        byID[item.bookingID] = item
                    } else {
                        context.delete(item)
                    }
                }
                for record in records {
                    if let item = byID[record.id] {
                        if item.record.isClosed, !record.isClosed { reopened.append(record.id) }
                        item.apply(record, fetchedAt: now)
                    } else {
                        let item = BookingItem(record, source: source, fetchedAt: now)
                        context.insert(item)
                        byID[record.id] = item
                    }
                }
                let keep = Set(records.map(\.id))
                let remove = replaceAll ? Set(byID.keys).subtracting(keep) : Set(deletedIDs).subtracting(keep)
                for id in remove {
                    if let item = byID[id] {
                        context.delete(item)
                        deleted += 1
                    }
                }
                return (records.count, deleted, reopened)
            }
        } catch let error as StoreError {
            throw error
        } catch {
            throw .saveFailed(.college)
        }
    }

    /// Deletes every booking of `source` (the source was disconnected).
    public func removeAll(source: SourceID) async throws(StoreError) {
        let sourceUUID = source.rawValue
        do {
            try await stores.college.perform { context in
                try context.fetch(FetchDescriptor<BookingItem>(predicate: #Predicate { $0.sourceUUID == sourceUUID })).forEach(context.delete)
            }
        } catch let error as StoreError {
            throw error
        } catch {
            throw .saveFailed(.college)
        }
    }
}
