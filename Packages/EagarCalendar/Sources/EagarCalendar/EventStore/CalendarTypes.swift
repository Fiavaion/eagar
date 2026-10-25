import EagarCore
import Foundation

/// Whether a calendar holds events or reminders.
public enum CalendarEntity: String, Sendable, Codable, CaseIterable {
    case event, reminder
}

/// The account type behind a calendar, as EventKit reports it.
public enum CalendarSourceKind: String, Sendable, Codable, CaseIterable {
    /// On this device only.
    case local
    /// iCloud (CalDAV to Apple). Data synced to iCloud by Apple Calendar or Reminders.
    case iCloud
    /// CalDAV accounts other than iCloud, including Google accounts added in Settings.
    case calDAV
    case exchange
    case subscribed
    case birthdays
    case other
}

/// A calendar or reminder list, as a value. Eagar stores references, not copies (BD-14).
public struct CalendarInfo: Sendable, Hashable, Identifiable {
    /// EventKit `calendarIdentifier`.
    public let id: String
    public let title: String
    /// The account name, e.g. an email address. Used only to propose a college tag.
    public let accountTitle: String
    public let sourceKind: CalendarSourceKind
    public let entity: CalendarEntity
    public let allowsModification: Bool

    public init(id: String, title: String, accountTitle: String, sourceKind: CalendarSourceKind, entity: CalendarEntity, allowsModification: Bool) {
        self.id = id
        self.title = title
        self.accountTitle = accountTitle
        self.sourceKind = sourceKind
        self.entity = entity
        self.allowsModification = allowsModification
    }
}

/// How an event affects free/busy.
public enum EventAvailability: String, Sendable, Codable, CaseIterable {
    case busy, free, tentative, unavailable, notSupported
}

/// An event read from EventKit, as a value. Not persisted by Eagar.
public struct CalendarEvent: Sendable, Hashable, Identifiable {
    /// EventKit `eventIdentifier` combined with the occurrence start, unique per occurrence.
    public let id: String
    public let calendarID: String
    public let title: String
    public let location: String?
    public let start: Date
    public let end: Date
    public let isAllDay: Bool
    public let availability: EventAvailability

    public init(id: String, calendarID: String, title: String, location: String? = nil, start: Date, end: Date, isAllDay: Bool = false, availability: EventAvailability = .busy) {
        self.id = id
        self.calendarID = calendarID
        self.title = title
        self.location = location
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.availability = availability
    }
}

/// An event together with the data class of its calendar (BD-03).
public struct ClassifiedEvent: Sendable, Hashable, Identifiable, Classified {
    public let event: CalendarEvent
    public let dataClass: DataClass
    public var id: String { event.id }
    public var sourceID: SourceID? { nil }

    public init(event: CalendarEvent, dataClass: DataClass) {
        self.event = event
        self.dataClass = dataClass
    }
}

/// A new or edited event to write through EventKit (FR-CAL-04).
public struct EventDraft: Sendable, Hashable {
    public var title: String
    public var start: Date
    public var end: Date
    public var isAllDay: Bool
    public var notes: String?

    public init(title: String, start: Date, end: Date, isAllDay: Bool = false, notes: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.notes = notes
    }
}

/// A reminder to write through EventKit (FR-DL-03).
public struct ReminderDraft: Sendable, Hashable {
    public var title: String
    public var due: Date?
    public var notes: String?

    public init(title: String, due: Date?, notes: String? = nil) {
        self.title = title
        self.due = due
        self.notes = notes
    }
}

/// EventKit authorisation for events and reminders.
public enum CalendarAccess: String, Sendable, CaseIterable {
    case notDetermined, denied, restricted, writeOnly, fullAccess
}

public enum CalendarError: Error, Equatable, Sendable, LogSafe {
    case accessDenied
    case calendarNotFound
    case readOnlyCalendar
    /// A write would put college-derived content into a non-college calendar (FR-CAL-04).
    case crossBoundaryWrite
    case saveFailed
    case fetchFailed

    public var logDescription: String {
        switch self {
        case .accessDenied: "accessDenied"
        case .calendarNotFound: "calendarNotFound"
        case .readOnlyCalendar: "readOnlyCalendar"
        case .crossBoundaryWrite: "crossBoundaryWrite"
        case .saveFailed: "saveFailed"
        case .fetchFailed: "fetchFailed"
        }
    }
}

/// The EventKit surface Eagar uses, behind a protocol so logic is testable with a fake.
public protocol EventStoreAdapting: Sendable {
    func access(for entity: CalendarEntity) -> CalendarAccess
    /// Requests full access to events and reminders (FR-CAL-01). Returns whether both were granted.
    func requestFullAccess() async throws(CalendarError) -> Bool
    func calendars(for entity: CalendarEntity) -> [CalendarInfo]
    func events(in interval: DateInterval, calendarIDs: Set<String>?) async throws(CalendarError) -> [CalendarEvent]
    /// Saves a new event; returns its identifier.
    func saveEvent(_ draft: EventDraft, toCalendar calendarID: String) async throws(CalendarError) -> String
    /// Saves a new reminder; returns its identifier.
    func saveReminder(_ draft: ReminderDraft, toList listID: String) async throws(CalendarError) -> String
    func removeReminder(id: String) async throws(CalendarError)
}
