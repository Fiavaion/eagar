import Foundation
import Testing
import EagarCalendar
import EagarCalendarTestSupport

struct FakeEventStoreTests {
    @Test func filtersEventsByIntervalAndCalendar() async throws {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let store = FakeEventStore(events: [
            CalendarEvent(id: "a", calendarID: "c1", title: "A", start: start, end: start + 3600),
            CalendarEvent(id: "b", calendarID: "c2", title: "B", start: start + 7200, end: start + 9000),
        ])
        let all = try await store.events(in: DateInterval(start: start, duration: 86_400), calendarIDs: nil)
        #expect(all.map(\.id) == ["a", "b"])
        let one = try await store.events(in: DateInterval(start: start, duration: 86_400), calendarIDs: ["c2"])
        #expect(one.map(\.id) == ["b"])
    }
}
