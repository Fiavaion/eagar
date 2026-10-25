import EagarCore
import EagarStore
import Foundation
import SwiftData

/// Domains whose accounts are college sources (FR-CORE-04). The Canvas host is added when known.
public enum CollegeDomains {
    public static let `default`: Set<String> = ["ncad.ie"]

    /// Whether an account title (usually an email address) belongs to one of `domains`.
    public static func matches(_ accountTitle: String, domains: Set<String> = Self.default) -> Bool {
        let host = accountTitle.split(separator: "@").last.map { $0.lowercased() } ?? ""
        return domains.contains { domain in host == domain || host.hasSuffix("." + domain) }
    }
}

/// Mark's college/personal tag for one calendar or reminder list (FR-CAL-02, PRD §7.3 `CalendarRef`).
///
/// A college calendar's reference lives in CollegeStore, a personal one in PersonalStore.
@Model
public final class CalendarRef: Classified {
    var calendarIdentifier: String = ""
    var entityRaw: String = CalendarEntity.event.rawValue
    var dataClassRaw: String = DataClass.college.rawValue
    var includeInBrief: Bool = true
    var taggedAt: Date = Date.distantPast

    init(calendarID: String, entity: CalendarEntity, dataClass: DataClass, includeInBrief: Bool, at date: Date) {
        calendarIdentifier = calendarID
        entityRaw = entity.rawValue
        dataClassRaw = dataClass.rawValue
        self.includeInBrief = includeInBrief
        taggedAt = date
    }

    /// Unknown raw values read as `college`.
    public var dataClass: DataClass { DataClass(rawValue: dataClassRaw) ?? .college }
    public var sourceID: SourceID? { nil }
}

/// A calendar's tag as a value.
public struct CalendarTag: Sendable, Hashable {
    public let calendarID: String
    public let dataClass: DataClass
    public let includeInBrief: Bool
    /// `false` when the tag is only Eagar's proposal and Mark has not confirmed it.
    public let confirmed: Bool
}

/// Proposes, stores and applies calendar tags.
public final class CalendarTagStore: Sendable {
    private let stores: EagarStores
    private let clock: any EagarClock
    private let collegeDomains: Set<String>

    public init(stores: EagarStores, clock: any EagarClock = SystemClock(), collegeDomains: Set<String> = CollegeDomains.default) {
        self.stores = stores
        self.clock = clock
        self.collegeDomains = collegeDomains
    }

    /// Eagar's proposal for an untagged calendar: college if its account or its title names a
    /// college domain (FR-CAL-02), otherwise personal. A proposal is only shown to Mark; until he
    /// confirms it, the calendar is treated as college (see ``CalendarClassifier``).
    public func proposedClass(for calendar: CalendarInfo) -> DataClass {
        let named = CollegeDomains.matches(calendar.accountTitle, domains: collegeDomains)
            || collegeDomains.contains { calendar.title.localizedCaseInsensitiveContains($0) }
        return named ? .college : .personal
    }

    /// Tags for `calendars`: Mark's confirmed tags where they exist, proposals otherwise.
    public func tags(for calendars: [CalendarInfo]) async throws(StoreError) -> [String: CalendarTag] {
        var confirmed: [String: CalendarTag] = [:]
        for store in [stores.personal, stores.college] {
            let rows = try await store.fetch(FetchDescriptor<CalendarRef>()) {
                CalendarTag(calendarID: $0.calendarIdentifier, dataClass: $0.dataClass, includeInBrief: $0.includeInBrief, confirmed: true)
            }
            for row in rows {
                // If a calendar somehow has rows in both stores, the more restrictive class wins.
                if let existing = confirmed[row.calendarID], existing.dataClass >= row.dataClass { continue }
                confirmed[row.calendarID] = row
            }
        }
        var result: [String: CalendarTag] = [:]
        for calendar in calendars {
            result[calendar.id] = confirmed[calendar.id]
                ?? CalendarTag(calendarID: calendar.id, dataClass: proposedClass(for: calendar), includeInBrief: true, confirmed: false)
        }
        return result
    }

    /// Records Mark's tag. Retagging moves the reference to the store its new class belongs in.
    public func setTag(_ calendar: CalendarInfo, dataClass: DataClass, includeInBrief: Bool = true) async throws(StoreError) {
        let id = calendar.id
        for store in [stores.personal, stores.college] {
            try await deleteRefs(in: store, calendarID: id)
        }
        let ref = CalendarRef(calendarID: id, entity: calendar.entity, dataClass: dataClass, includeInBrief: includeInBrief, at: clock.now())
        try await stores.insert(ref)
    }

    private func deleteRefs(in store: ClassifiedStore, calendarID: String) async throws(StoreError) {
        do {
            try await store.perform { context in
                let refs = try context.fetch(FetchDescriptor<CalendarRef>(predicate: #Predicate { $0.calendarIdentifier == calendarID }))
                refs.forEach(context.delete)
            }
        } catch let error as StoreError {
            throw error
        } catch {
            throw .saveFailed(store.kind)
        }
    }
}

/// Applies tags to events (BD-03, D-017).
///
/// Fails closed: an event counts as personal only when Mark has **confirmed** its calendar as
/// personal. Unconfirmed calendars (whatever Eagar proposed) and unknown calendars are treated as
/// college, so a Canvas or NCAD feed subscribed under some other account can never be shown or
/// sent as personal before Mark has looked at it.
public enum CalendarClassifier {
    public static func effectiveClass(_ tag: CalendarTag?) -> DataClass {
        guard let tag, tag.confirmed else { return .college }
        return tag.dataClass
    }

    public static func classify(_ events: [CalendarEvent], tags: [String: CalendarTag]) -> [ClassifiedEvent] {
        events.map { ClassifiedEvent(event: $0, dataClass: effectiveClass(tags[$0.calendarID])) }
    }
}

/// Writes events through EventKit, refusing to put college-derived content into a calendar that
/// is not tagged college (FR-CAL-04).
public struct CalendarWriter: Sendable {
    let store: any EventStoreAdapting

    public init(store: any EventStoreAdapting) {
        self.store = store
    }

    /// - Parameter derivedFrom: the classes of everything the draft was built from.
    public func save(_ draft: EventDraft, derivedFrom: [DataClass], to calendar: CalendarInfo, tag: CalendarTag) async throws(CalendarError) -> String {
        let draftClass = DataClass.max(of: derivedFrom)
        if draftClass == .college, tag.dataClass != .college {
            EagarLog(.store).notice("refused a college-derived event write to a non-college calendar")
            throw .crossBoundaryWrite
        }
        return try await store.saveEvent(draft, toCalendar: calendar.id)
    }
}

/// FR-CAL-06: whether the NCAD calendar seems to be missing from Apple Calendar.
public enum CalendarDiagnosis {
    public static func isCollegeCalendarMissing(_ calendars: [CalendarInfo], domains: Set<String> = CollegeDomains.default) -> Bool {
        !calendars.contains { $0.entity == .event && CollegeDomains.matches($0.accountTitle, domains: domains) }
    }
}
