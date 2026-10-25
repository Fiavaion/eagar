import EagarCore
import EventKit
import Foundation
import Synchronization

/// The real `EventStoreAdapting`, over one `EKEventStore`.
///
/// Every use of the store happens inside a `Mutex`, so calls from different tasks never touch
/// it concurrently and no `@unchecked Sendable` is needed. Eagar reads events into values and
/// never keeps `EKEvent` objects (BD-14: store references, not copies).
public final class EventKitAdapter: EventStoreAdapting {
    private let store = Mutex(EKEventStore())
    private let log = EagarLog(.store)

    public init() {}

    public func access(for entity: CalendarEntity) -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: entity == .event ? .event : .reminder) {
        case .notDetermined: .notDetermined
        case .restricted: .restricted
        case .denied: .denied
        case .fullAccess: .fullAccess
        case .writeOnly: .writeOnly
        @unknown default: .denied
        }
    }

    public func requestFullAccess() async throws(CalendarError) -> Bool {
        let events = await request { store, done in store.requestFullAccessToEvents { granted, _ in done(granted) } }
        let reminders = await request { store, done in store.requestFullAccessToReminders { granted, _ in done(granted) } }
        log.notice("calendar access: events \(events), reminders \(reminders)")
        return events && reminders
    }

    public func calendars(for entity: CalendarEntity) -> [CalendarInfo] {
        store.withLock { store in
            store.calendars(for: entity == .event ? .event : .reminder).map { Self.info($0, entity: entity) }
        }
    }

    public func events(in interval: DateInterval, calendarIDs: Set<String>?) async throws(CalendarError) -> [CalendarEvent] {
        guard access(for: .event) == .fullAccess else { throw .accessDenied }
        return store.withLock { store in
            let calendars = calendarIDs.map { ids in store.calendars(for: .event).filter { ids.contains($0.calendarIdentifier) } }
            if let calendars, calendars.isEmpty { return [] }
            let predicate = store.predicateForEvents(withStart: interval.start, end: interval.end, calendars: calendars)
            return store.events(matching: predicate).map(Self.event)
        }
    }

    public func saveEvent(_ draft: EventDraft, toCalendar calendarID: String) async throws(CalendarError) -> String {
        try store.withLock { store throws(CalendarError) in
            guard let calendar = store.calendar(withIdentifier: calendarID) else { throw .calendarNotFound }
            guard calendar.allowsContentModifications else { throw .readOnlyCalendar }
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = draft.title
            event.startDate = draft.start
            event.endDate = draft.end
            event.isAllDay = draft.isAllDay
            event.notes = draft.notes
            do {
                try store.save(event, span: .thisEvent, commit: true)
            } catch {
                throw .saveFailed
            }
            return event.eventIdentifier ?? event.calendarItemIdentifier
        }
    }

    public func saveReminder(_ draft: ReminderDraft, toList listID: String) async throws(CalendarError) -> String {
        try store.withLock { store throws(CalendarError) in
            guard let list = store.calendar(withIdentifier: listID) else { throw .calendarNotFound }
            guard list.allowsContentModifications else { throw .readOnlyCalendar }
            let reminder = EKReminder(eventStore: store)
            reminder.calendar = list
            reminder.title = draft.title
            reminder.notes = draft.notes
            if let due = draft.due {
                reminder.dueDateComponents = Calendar.current.dateComponents(
                    [.year, .month, .day, .hour, .minute, .timeZone], from: due
                )
            }
            do {
                try store.save(reminder, commit: true)
            } catch {
                throw .saveFailed
            }
            return reminder.calendarItemIdentifier
        }
    }

    public func removeReminder(id: String) async throws(CalendarError) {
        try store.withLock { store throws(CalendarError) in
            guard let reminder = store.calendarItem(withIdentifier: id) as? EKReminder else { return }
            do {
                try store.remove(reminder, commit: true)
            } catch {
                throw .saveFailed
            }
        }
    }

    // MARK: - Mapping

    private func request(_ ask: (EKEventStore, @escaping @Sendable (Bool) -> Void) -> Void) async -> Bool {
        await withCheckedContinuation { continuation in
            store.withLock { store in
                ask(store) { granted in continuation.resume(returning: granted) }
            }
        }
    }

    static func info(_ calendar: EKCalendar, entity: CalendarEntity) -> CalendarInfo {
        CalendarInfo(
            id: calendar.calendarIdentifier,
            title: calendar.title,
            accountTitle: calendar.source?.title ?? "",
            sourceKind: sourceKind(calendar.source),
            entity: entity,
            allowsModification: calendar.allowsContentModifications
        )
    }

    static func sourceKind(_ source: EKSource?) -> CalendarSourceKind {
        guard let source else { return .other }
        switch source.sourceType {
        case .local: return .local
        case .exchange: return .exchange
        case .mobileMe: return .iCloud
        case .calDAV: return source.title.caseInsensitiveCompare("iCloud") == .orderedSame ? .iCloud : .calDAV
        case .subscribed: return .subscribed
        case .birthdays: return .birthdays
        @unknown default: return .other
        }
    }

    static func event(_ event: EKEvent) -> CalendarEvent {
        let start = event.startDate ?? .distantPast
        let availability: EventAvailability = switch event.availability {
        case .busy: .busy
        case .free: .free
        case .tentative: .tentative
        case .unavailable: .unavailable
        case .notSupported: .notSupported
        @unknown default: .busy
        }
        return CalendarEvent(
            id: "\(event.eventIdentifier ?? event.calendarItemIdentifier)@\(Int(start.timeIntervalSince1970))",
            calendarID: event.calendar?.calendarIdentifier ?? "",
            title: event.title ?? "",
            location: event.location,
            start: start,
            end: event.endDate ?? start,
            isAllDay: event.isAllDay,
            availability: availability
        )
    }
}
