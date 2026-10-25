import EagarCalendar
import Foundation
import Synchronization

/// A deterministic, synthetic calendar for UI tests, previews and screenshots, used when the app
/// is launched with `-EagarFakeCalendar YES`. Never touches EventKit; holds no real data.
///
/// One personal calendar ("Home"), one college calendar on `demo@ncad.ie` ("NCAD") and one
/// reminder list, with a few events on the day containing `now`.
final class DemoEventStore: EventStoreAdapting {
    static let homeID = "demo.calendar.home"
    static let collegeID = "demo.calendar.ncad"
    static let remindersID = "demo.reminders.home"

    private struct State {
        var access: CalendarAccess
        var events: [CalendarEvent]
        var savedReminders: [String: ReminderDraft] = [:]
        var savedEvents = 0
    }

    private let calendarList: [CalendarInfo] = [
        CalendarInfo(id: homeID, title: "Home", accountTitle: "iCloud", sourceKind: .iCloud, entity: .event, allowsModification: true),
        CalendarInfo(id: collegeID, title: "NCAD", accountTitle: "demo@ncad.ie", sourceKind: .calDAV, entity: .event, allowsModification: true),
        CalendarInfo(id: remindersID, title: "Reminders", accountTitle: "iCloud", sourceKind: .iCloud, entity: .reminder, allowsModification: true),
    ]
    private let state: Mutex<State>

    init(now: Date = Date(), calendar: Calendar = .current, access: CalendarAccess = .fullAccess) {
        state = Mutex(State(access: access, events: Self.events(on: now, calendar: calendar)))
    }

    /// Two all-day events (so the brief always has a personal and a college item, whatever the
    /// time) and four timed events spread over the day.
    static func events(on day: Date, calendar: Calendar) -> [CalendarEvent] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        func at(_ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(bySettingHour: hour, minute: minute, second: 0, of: start) ?? start
        }
        return [
            CalendarEvent(id: "demo.bins", calendarID: homeID, title: "Bin collection", start: start, end: end, isAllDay: true, availability: .free),
            CalendarEvent(id: "demo.week", calendarID: collegeID, title: "Submission week", start: start, end: end, isAllDay: true, availability: .free),
            CalendarEvent(id: "demo.crit", calendarID: collegeID, title: "Studio crit", location: "Studio 4", start: at(9, 30), end: at(10, 30)),
            CalendarEvent(id: "demo.lunch", calendarID: homeID, title: "Lunch with Sam", start: at(13), end: at(14)),
            CalendarEvent(id: "demo.print", calendarID: collegeID, title: "Printmaking workshop", start: at(15), end: at(16, 30)),
            CalendarEvent(id: "demo.climb", calendarID: homeID, title: "Climbing", start: at(19), end: at(20, 30)),
        ]
    }

    func access(for entity: CalendarEntity) -> CalendarAccess { state.withLock { $0.access } }

    func requestFullAccess() async throws(CalendarError) -> Bool {
        state.withLock { $0.access = .fullAccess }
        return true
    }

    func calendars(for entity: CalendarEntity) -> [CalendarInfo] {
        guard access(for: entity) == .fullAccess else { return [] }
        return calendarList.filter { $0.entity == entity }
    }

    func events(in interval: DateInterval, calendarIDs: Set<String>?) async throws(CalendarError) -> [CalendarEvent] {
        try state.withLock { s throws(CalendarError) in
            guard s.access == .fullAccess else { throw .accessDenied }
            return s.events.filter { event in
                event.end > interval.start && event.start < interval.end && (calendarIDs?.contains(event.calendarID) ?? true)
            }
        }
    }

    func saveEvent(_ draft: EventDraft, toCalendar calendarID: String) async throws(CalendarError) -> String {
        guard calendarList.contains(where: { $0.id == calendarID && $0.entity == .event }) else { throw .calendarNotFound }
        return state.withLock { s in
            s.savedEvents += 1
            return "demo.event.\(s.savedEvents)"
        }
    }

    func saveReminder(_ draft: ReminderDraft, toList listID: String) async throws(CalendarError) -> String {
        guard calendarList.contains(where: { $0.id == listID && $0.entity == .reminder }) else { throw .calendarNotFound }
        return state.withLock { s in
            let id = "demo.reminder.\(s.savedReminders.count + 1)"
            s.savedReminders[id] = draft
            return id
        }
    }

    func removeReminder(id: String) async throws(CalendarError) {
        _ = state.withLock { $0.savedReminders.removeValue(forKey: id) }
    }
}
