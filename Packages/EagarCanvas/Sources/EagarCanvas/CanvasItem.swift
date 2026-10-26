import EagarCore
import EagarStore
import Foundation
import SwiftData

/// What a Canvas calendar entry is.
public enum CanvasItemKind: String, Codable, Sendable, CaseIterable, LogSafe {
    /// An assignment due date: becomes a deadline (FR-CANVAS-02).
    case assignment
    /// A calendar event (class, visit, reading week): shown, not a deadline.
    case event

    public var logDescription: String { rawValue }
}

/// One Canvas calendar entry, as a value.
public struct CanvasEntry: Sendable, Hashable, Identifiable {
    /// The VEVENT UID, e.g. `event-assignment-1001`.
    public let id: String
    public let kind: CanvasItemKind
    public let title: String
    /// The course code Canvas appends to the summary in brackets, e.g. `SYN101`.
    public let courseCode: String?
    /// Canvas's numeric course ID, from the entry's link (`course_501`, `/courses/501/`).
    public let courseID: String?
    public let start: Date?
    public let end: Date?
    /// For assignments: the due time (all-day: the start of the due day).
    public let dueAt: Date?
    public let isAllDay: Bool
    /// The entry's page on Canvas. Requires a login; not the feed URL.
    public let pageURL: URL?
    public let lastModified: Date?

    public init(
        id: String, kind: CanvasItemKind, title: String, courseCode: String? = nil, courseID: String? = nil, start: Date? = nil,
        end: Date? = nil, dueAt: Date? = nil, isAllDay: Bool = false, pageURL: URL? = nil, lastModified: Date? = nil
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.courseCode = courseCode
        self.courseID = courseID
        self.start = start
        self.end = end
        self.dueAt = dueAt
        self.isAllDay = isAllDay
        self.pageURL = pageURL
        self.lastModified = lastModified
    }
}

/// A Canvas calendar entry (PRD §7.3 `CanvasItem`). Always `college` (FR-CANVAS-02), so it can
/// only be saved in CollegeStore. CloudKit-compatible; one record per (`sourceUUID`, `uid`) is
/// enforced by ``CanvasRepository``. Holds no feed URL (invariant 6).
@Model
public final class CanvasItem: Classified {
    public var uid: String = ""
    public var sourceUUID: UUID = UUID()
    public var kindRaw: String = CanvasItemKind.event.rawValue
    public var title: String = ""
    public var courseCode: String?
    public var courseID: String?
    public var startAt: Date?
    public var endAt: Date?
    public var dueAt: Date?
    public var isAllDay: Bool = false
    public var pageURL: String?
    public var lastModified: Date?
    public var dataClassRaw: String = DataClass.college.rawValue
    public var fetchedAt: Date = Date.distantPast

    public init(_ entry: CanvasEntry, source: SourceID, fetchedAt: Date) {
        uid = entry.id
        sourceUUID = source.rawValue
        apply(entry, fetchedAt: fetchedAt)
    }

    /// Unknown raw values read as `college`.
    public var dataClass: DataClass { DataClass(rawValue: dataClassRaw) ?? .college }
    public var sourceID: SourceID? { SourceID(sourceUUID) }

    public func apply(_ entry: CanvasEntry, fetchedAt: Date) {
        kindRaw = entry.kind.rawValue
        title = entry.title
        courseCode = entry.courseCode
        courseID = entry.courseID
        startAt = entry.start
        endAt = entry.end
        dueAt = entry.dueAt
        isAllDay = entry.isAllDay
        pageURL = entry.pageURL?.absoluteString
        lastModified = entry.lastModified
        self.fetchedAt = fetchedAt
    }

    public var entry: CanvasEntry {
        CanvasEntry(
            id: uid, kind: CanvasItemKind(rawValue: kindRaw) ?? .event, title: title, courseCode: courseCode, courseID: courseID,
            start: startAt, end: endAt, dueAt: dueAt, isAllDay: isAllDay, pageURL: pageURL.flatMap(URL.init(string:)),
            lastModified: lastModified
        )
    }
}

/// Reads and upserts ``CanvasItem``s in CollegeStore.
public struct CanvasRepository: Sendable {
    let stores: EagarStores

    public init(stores: EagarStores) {
        self.stores = stores
    }

    /// Every stored entry, optionally for one source, by due or start time.
    public func all(source: SourceID? = nil) async throws(StoreError) -> [CanvasEntry] {
        let descriptor: FetchDescriptor<CanvasItem>
        if let id = source?.rawValue {
            descriptor = FetchDescriptor(predicate: #Predicate { $0.sourceUUID == id })
        } else {
            descriptor = FetchDescriptor()
        }
        return try await stores.college.fetch(descriptor) { $0.entry }
            .sorted { ($0.dueAt ?? $0.start ?? .distantFuture) < ($1.dueAt ?? $1.start ?? .distantFuture) }
    }

    /// Replaces the source's entries with `entries` (the feed is always read in full).
    func replace(with entries: [CanvasEntry], source: SourceID, now: Date) async throws(StoreError) -> (upserted: Int, deleted: Int) {
        let sourceUUID = source.rawValue
        do {
            return try await stores.college.perform { context in
                var byUID: [String: CanvasItem] = [:]
                for item in try context.fetch(FetchDescriptor<CanvasItem>(predicate: #Predicate { $0.sourceUUID == sourceUUID })) {
                    if byUID[item.uid] == nil { byUID[item.uid] = item } else { context.delete(item) }
                }
                for entry in entries {
                    if let item = byUID[entry.id] {
                        item.apply(entry, fetchedAt: now)
                    } else {
                        let item = CanvasItem(entry, source: source, fetchedAt: now)
                        context.insert(item)
                        byUID[entry.id] = item
                    }
                }
                let stale = Set(byUID.keys).subtracting(entries.map(\.id))
                for uid in stale { if let item = byUID[uid] { context.delete(item) } }
                return (entries.count, stale.count)
            }
        } catch let error as StoreError {
            throw error
        } catch {
            throw .saveFailed(.college)
        }
    }

    /// Deletes every entry of `source` (the source was disconnected).
    public func removeAll(source: SourceID) async throws(StoreError) {
        _ = try await replace(with: [], source: source, now: .distantPast)
    }
}
