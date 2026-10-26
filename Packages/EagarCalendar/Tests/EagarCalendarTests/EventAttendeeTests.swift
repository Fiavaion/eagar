import Foundation
import Testing
@testable import EagarCalendar

/// Attendee addresses feed keep-in-touch inference (FR-PEOPLE-03).
struct EventAttendeeTests {
    @Test(arguments: [
        ("mailto:Aoife.Byrne@example.ie", "aoife.byrne@example.ie"),
        ("MAILTO:niamh@example.com", "niamh@example.com"),
        ("mailto:ciaran%40example.org", "ciaran@example.org"),
        ("mailto:sean@example.ie?subject=x", "sean@example.ie"),
    ])
    func mailtoURLsGiveLowerCasedAddresses(raw: String, expected: String) throws {
        let url = try #require(URL(string: raw))
        #expect(EventKitAdapter.emailAddress(fromParticipantURL: url) == expected)
    }

    @Test(arguments: ["https://example.ie/aoife", "mailto:nobody", "urn:uuid:1234"])
    func otherURLsGiveNothing(raw: String) throws {
        let url = try #require(URL(string: raw))
        #expect(EventKitAdapter.emailAddress(fromParticipantURL: url) == nil)
    }

    @Test func attendeesDefaultToEmpty() {
        let event = CalendarEvent(id: "a", calendarID: "c", title: "A", start: Date(), end: Date())
        #expect(event.attendeeEmails.isEmpty)
    }
}
