import EagarCore
import EagarStore
import Foundation
import SwiftData

/// What happened (FR-SUG-01). Content-free by design: entries hold kinds and opaque references,
/// never titles or text.
public enum EventLogKind: String, Codable, Sendable, CaseIterable, LogSafe {
    case briefOpened
    case briefCompleted
    case itemOpened
    case itemDone
    case itemSnoozed
    case itemDismissed
    case itemRescheduled
    case thumbsUp
    case thumbsDown

    public var logDescription: String { rawValue }
}

/// One event-log row (PRD §7.3 `EventLogEntry`). Append-only; college entries live in
/// CollegeStore. CloudKit-compatible.
@Model
public final class EventLogEntry: Classified {
    var entryUUID: UUID = UUID()
    var at: Date = Date.distantPast
    var kindRaw: String = EventLogKind.briefOpened.rawValue
    /// An opaque reference, e.g. a brief ID or an item ID. Never content.
    var subjectRef: String = ""
    /// A small numeric feature, e.g. a duration in seconds. Optional.
    var value: Double?
    var dataClassRaw: String = DataClass.college.rawValue

    init(at: Date, kind: EventLogKind, subjectRef: String, value: Double?, dataClass: DataClass) {
        self.at = at
        kindRaw = kind.rawValue
        self.subjectRef = subjectRef
        self.value = value
        dataClassRaw = dataClass.rawValue
    }

    public var dataClass: DataClass { DataClass(rawValue: dataClassRaw) ?? .college }
    public var sourceID: SourceID? { nil }
}

/// A read-only copy of an entry.
public struct EventLogRecord: Sendable, Equatable {
    public let at: Date
    public let kind: EventLogKind
    public let subjectRef: String
    public let value: Double?
    public let dataClass: DataClass
}

/// Writes and reads the event log.
public final class EventLog: Sendable {
    private let stores: EagarStores
    private let clock: any EagarClock

    public init(stores: EagarStores, clock: any EagarClock = SystemClock()) {
        self.stores = stores
        self.clock = clock
    }

    /// Appends an entry. `dataClass` is the class of the thing acted on.
    public func record(_ kind: EventLogKind, subject: String, value: Double? = nil, dataClass: DataClass) async throws(StoreError) {
        try await stores.insert(EventLogEntry(at: clock.now(), kind: kind, subjectRef: subject, value: value, dataClass: dataClass))
    }

    /// Entries from both stores since `date`, oldest first.
    public func records(since date: Date = .distantPast) async throws(StoreError) -> [EventLogRecord] {
        var all: [EventLogRecord] = []
        for store in [stores.personal, stores.college] {
            all += try await store.fetch(FetchDescriptor<EventLogEntry>(predicate: #Predicate { $0.at >= date })) {
                EventLogRecord(at: $0.at, kind: EventLogKind(rawValue: $0.kindRaw) ?? .itemOpened, subjectRef: $0.subjectRef, value: $0.value, dataClass: $0.dataClass)
            }
        }
        return all.sorted { $0.at < $1.at }
    }
}
