import EagarCalendar
import Foundation
import Synchronization

/// In-memory `EventStoreAdapting` for tests. Records every write.
public final class FakeEventStore: EventStoreAdapting {
    public struct State: Sendable {
        public var access: CalendarAccess = .fullAccess
        public var grantOnRequest = true
        public var calendars: [CalendarInfo] = []
        public var events: [CalendarEvent] = []
        public var savedEvents: [(calendarID: String, draft: EventDraft)] = []
        public var savedReminders: [(listID: String, draft: ReminderDraft, id: String)] = []
        public var removedReminderIDs: [String] = []
    }

    public let state: Mutex<State>

    public init(calendars: [CalendarInfo] = [], events: [CalendarEvent] = [], access: CalendarAccess = .fullAccess) {
        var initial = State()
        initial.calendars = calendars
        initial.events = events
        initial.access = access
        state = Mutex(initial)
    }

    public func access(for entity: CalendarEntity) -> CalendarAccess { state.withLock { $0.access } }

    public func requestFullAccess() async throws(CalendarError) -> Bool {
        state.withLock {
            if $0.grantOnRequest { $0.access = .fullAccess }
            return $0.grantOnRequest
        }
    }

    public func calendars(for entity: CalendarEntity) -> [CalendarInfo] {
        state.withLock { $0.calendars.filter { $0.entity == entity } }
    }

    public func events(in interval: DateInterval, calendarIDs: Set<String>?) async throws(CalendarError) -> [CalendarEvent] {
        try state.withLock { s throws(CalendarError) in
            guard s.access == .fullAccess else { throw .accessDenied }
            return s.events.filter { event in
                event.end > interval.start && event.start < interval.end && (calendarIDs?.contains(event.calendarID) ?? true)
            }
        }
    }

    public func saveEvent(_ draft: EventDraft, toCalendar calendarID: String) async throws(CalendarError) -> String {
        try state.withLock { s throws(CalendarError) in
            guard let calendar = s.calendars.first(where: { $0.id == calendarID && $0.entity == .event }) else { throw .calendarNotFound }
            guard calendar.allowsModification else { throw .readOnlyCalendar }
            s.savedEvents.append((calendarID, draft))
            return "event-\(s.savedEvents.count)"
        }
    }

    public func saveReminder(_ draft: ReminderDraft, toList listID: String) async throws(CalendarError) -> String {
        try state.withLock { s throws(CalendarError) in
            guard s.calendars.contains(where: { $0.id == listID && $0.entity == .reminder }) else { throw .calendarNotFound }
            let id = "reminder-\(s.savedReminders.count + 1)"
            s.savedReminders.append((listID, draft, id))
            return id
        }
    }

    public func removeReminder(id: String) async throws(CalendarError) {
        state.withLock { $0.removedReminderIDs.append(id) }
    }
}
