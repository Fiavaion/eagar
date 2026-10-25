import EagarCalendar
import EagarCore
import Foundation

/// Synthetic fixtures for the availability tests (FR-CAL-03). Reference day: Wednesday 14 October 2026.
enum AvailabilityFixtures {
    static func calendar(_ identifier: String) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: identifier)!
        return calendar
    }

    static let dublin = calendar("Europe/Dublin")
    static let newYork = calendar("America/New_York")
    static let utc = calendar("UTC")

    /// An instant written in UTC, e.g. `"2026-10-14T09:00:00Z"`.
    static func at(_ iso: String) -> Date {
        try! Date(iso, strategy: .iso8601)
    }

    /// A wall-clock time in `calendar`'s zone.
    static func local(_ calendar: Calendar, _ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    static func window(_ start: String, _ end: String) -> DateInterval {
        DateInterval(start: at(start), end: at(end))
    }

    /// The reference working day in UTC: 08:00 to 18:00.
    static let day = window("2026-10-14T08:00:00Z", "2026-10-14T18:00:00Z")

    static func event(
        _ id: String,
        _ start: String,
        _ end: String,
        _ availability: EventAvailability = .busy,
        allDay: Bool = false,
        _ dataClass: DataClass = .personal
    ) -> ClassifiedEvent {
        event(id, at(start), at(end), availability, allDay: allDay, dataClass)
    }

    static func event(
        _ id: String,
        _ start: Date,
        _ end: Date,
        _ availability: EventAvailability = .busy,
        allDay: Bool = false,
        _ dataClass: DataClass = .personal
    ) -> ClassifiedEvent {
        ClassifiedEvent(
            event: CalendarEvent(id: id, calendarID: "cal", title: "Synthetic", start: start, end: end, isAllDay: allDay, availability: availability),
            dataClass: dataClass
        )
    }
}
