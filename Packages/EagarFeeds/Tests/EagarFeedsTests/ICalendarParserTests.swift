import Foundation
import Testing
@testable import EagarFeeds

/// RFC 5545 subset parser. All fixtures are synthetic.
struct ICalendarParserTests {
    let dublin = TimeZone(identifier: "Europe/Dublin")!

    func wrap(_ body: String) -> String {
        "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nPRODID:-//Synthetic//EN\r\n\(body)END:VCALENDAR\r\n"
    }

    func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    // MARK: Dates (table-driven)

    struct DateCase: Sendable, CustomTestStringConvertible {
        let line: String
        let expected: Date?
        let kind: ICalDate.Kind?
        var testDescription: String { line }
    }

    static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    static func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
        utcCalendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    static let dateCases: [DateCase] = [
        DateCase(line: "DTSTART:20261028T160000Z", expected: at(2026, 10, 28, 16), kind: .utc),
        // Dublin is UTC+1 (IST) until 25 Oct 2026, then UTC+0.
        DateCase(line: "DTSTART;TZID=Europe/Dublin:20261020T090000", expected: at(2026, 10, 20, 8), kind: .zoned("Europe/Dublin")),
        DateCase(line: "DTSTART;TZID=Europe/Dublin:20261102T090000", expected: at(2026, 11, 2, 9), kind: .zoned("Europe/Dublin")),
        DateCase(line: "DTSTART;TZID=America/New_York:20261105T235900", expected: at(2026, 11, 6, 4, 59), kind: .zoned("America/New_York")),
        DateCase(line: "DTSTART;TZID=\"Asia/Tokyo\":20261105T090000", expected: at(2026, 11, 5, 0), kind: .zoned("Asia/Tokyo")),
        DateCase(line: "DTSTART;TZID=/Europe/Paris:20261105T120000", expected: at(2026, 11, 5, 11), kind: .zoned("Europe/Paris")),
        DateCase(line: "DTSTART;TZID=Eastern Standard Time:20261105T120000", expected: at(2026, 11, 5, 17), kind: .zoned("America/New_York")),
        // Unknown TZID falls back to the parse zone (Dublin, UTC+0 in November).
        DateCase(line: "DTSTART;TZID=Mars/Olympus:20261105T120000", expected: at(2026, 11, 5, 12), kind: .floating),
        DateCase(line: "DTSTART:20261105T120000", expected: at(2026, 11, 5, 12), kind: .floating),
        DateCase(line: "DTSTART;VALUE=DATE:20261020", expected: at(2026, 10, 19, 23), kind: .allDay),
        DateCase(line: "DTSTART;VALUE=DATE:20261030", expected: at(2026, 10, 30), kind: .allDay),
        DateCase(line: "DTSTART:20261110", expected: at(2026, 11, 10), kind: .allDay),
        DateCase(line: "DTSTART:2026-11-10", expected: nil, kind: nil),
        DateCase(line: "DTSTART:20261340T120000Z", expected: nil, kind: nil),
        DateCase(line: "DTSTART:garbage", expected: nil, kind: nil),
    ]

    @Test(arguments: dateCases)
    func dates(_ c: DateCase) throws {
        let property = try #require(ICalendarParser.parseLine(c.line))
        let parsed = ICalendarParser.parseDate(property, timeZone: dublin, floatingZone: dublin)
        #expect(parsed?.date == c.expected)
        #expect(parsed?.kind == c.kind)
    }

    // MARK: Text and lines

    static let textCases: [(raw: String, text: String)] = [
        ("Plain", "Plain"),
        ("Comma\\, semicolon\\; backslash\\\\", "Comma, semicolon; backslash\\"),
        ("Line one\\nLine two\\NThree", "Line one\nLine two\nThree"),
        ("Trailing\\", "Trailing\\"),
        ("Unknown \\x escape", "Unknown x escape"),
    ]

    @Test(arguments: textCases)
    func unescapes(_ c: (raw: String, text: String)) {
        #expect(ICalendarParser.unescape(c.raw) == c.text)
    }

    @Test func unfoldsCRLFLFAndTabContinuations() {
        let text = "SUMMARY:Long \r\n title\nDESCRIPTION:a\n\tb\rLOCATION:x"
        #expect(ICalendarParser.unfold(text) == ["SUMMARY:Long title", "DESCRIPTION:ab", "LOCATION:x"])
    }

    @Test func parsesQuotedParametersContainingColonsAndSemicolons() throws {
        let property = try #require(ICalendarParser.parseLine("ATTENDEE;CN=\"Doe; J: Ph.D\";ROLE=CHAIR:mailto:someone@example.org"))
        #expect(property.name == "ATTENDEE")
        #expect(property.parameters["CN"] == "Doe; J: Ph.D")
        #expect(property.parameters["ROLE"] == "CHAIR")
        #expect(property.rawValue == "mailto:someone@example.org")
    }

    @Test(arguments: ["no colon here", ":value only", "BAD NAME:x", ""])
    func rejectsJunkLines(_ line: String) {
        #expect(ICalendarParser.parseLine(line) == nil)
    }

    // MARK: Documents

    @Test func parsesAnEventWithEveryLiftedProperty() throws {
        let text = wrap("""
        X-WR-CALNAME:Synthetic\r
        BEGIN:VEVENT\r
        UID:evt-1@example.org\r
        SUMMARY:Crit\\, studio 3\r
        DESCRIPTION:Bring \r
          sketches\\nand notes\r
        LOCATION:Room 1\r
        URL:https://example.org/e/1\r
        DTSTART:20261028T100000Z\r
        DTEND:20261028T110000Z\r
        DUE:20261028T160000Z\r
        STATUS:confirmed\r
        LAST-MODIFIED:20261020T080000Z\r
        X-CDB-STATUS:checked_out\r
        BEGIN:VALARM\r
        ACTION:DISPLAY\r
        DESCRIPTION:Alarm text must not leak into the event\r
        TRIGGER:-PT15M\r
        END:VALARM\r
        END:VEVENT\r

        """)
        let calendar = try ICalendarParser.parse(text, timeZone: dublin)
        #expect(calendar.name == "Synthetic")
        let event = try #require(calendar.events.first)
        #expect(calendar.events.count == 1)
        #expect(event.uid == "evt-1@example.org")
        #expect(event.summary == "Crit, studio 3")
        #expect(event.eventDescription == "Bring  sketches\nand notes")
        #expect(event.location == "Room 1")
        #expect(event.url == URL(string: "https://example.org/e/1"))
        #expect(event.start?.date == utc(2026, 10, 28, 10))
        #expect(event.end?.date == utc(2026, 10, 28, 11))
        #expect(event.due?.date == utc(2026, 10, 28, 16))
        #expect(event.status == "CONFIRMED")
        #expect(event.lastModified == utc(2026, 10, 20, 8))
        #expect(event.property("x-cdb-status")?.text == "checked_out")
        #expect(event.property("TRIGGER") == nil)
    }

    @Test func toleratesVTimezoneBlocksAndResolvesTZIDByName() throws {
        let text = wrap("""
        BEGIN:VTIMEZONE\r
        TZID:Europe/Dublin\r
        BEGIN:STANDARD\r
        DTSTART:19701025T020000\r
        TZOFFSETFROM:+0100\r
        TZOFFSETTO:+0000\r
        END:STANDARD\r
        END:VTIMEZONE\r
        BEGIN:VEVENT\r
        UID:z\r
        DTSTART;TZID=Europe/Dublin:20261020T090000\r
        END:VEVENT\r

        """)
        let calendar = try ICalendarParser.parse(text, timeZone: TimeZone(identifier: "UTC")!)
        #expect(calendar.events.count == 1)
        #expect(calendar.events[0].start?.date == utc(2026, 10, 20, 8))
    }

    @Test func calendarTimeZoneAppliesToFloatingTimes() throws {
        let text = wrap("X-WR-TIMEZONE:America/New_York\r\nBEGIN:VEVENT\r\nUID:f\r\nDTSTART:20261105T120000\r\nEND:VEVENT\r\n")
        let calendar = try ICalendarParser.parse(text, timeZone: dublin)
        #expect(calendar.events[0].start?.date == utc(2026, 11, 5, 17))
        #expect(calendar.events[0].start?.kind == .floating)
    }

    @Test func skipsJunkAndKeepsGoing() throws {
        let text = wrap("""
        this line is junk\r
        BEGIN:VEVENT\r
        UID:a\r
        <html>oops</html>\r
        SUMMARY:Kept\r
        END:VEVENT\r
        END:VTODO\r
        BEGIN:VEVENT\r
        UID:b\r
        BEGIN:VALARM\r
        TRIGGER:-PT5M\r
        END:VEVENT\r
        BEGIN:VEVENT\r
        UID:c\r
        END:VEVENT\r

        """)
        let calendar = try ICalendarParser.parse(text, timeZone: dublin)
        #expect(calendar.events.map(\.uid) == ["a", "b", "c"])
        #expect(calendar.events[0].summary == "Kept")
        #expect(calendar.skippedLineCount >= 2)
    }

    @Test func ignoresContentOutsideTheCalendar() throws {
        let text = "SUMMARY:before\r\n" + wrap("BEGIN:VEVENT\r\nUID:a\r\nEND:VEVENT\r\n") + "BEGIN:VEVENT\r\nUID:after\r\nEND:VEVENT\r\n"
        let calendar = try ICalendarParser.parse(text, timeZone: dublin)
        #expect(calendar.events.map(\.uid) == ["a"])
    }

    @Test func emptyCalendarHasNoEvents() throws {
        #expect(try ICalendarParser.parse(wrap(""), timeZone: dublin).events.isEmpty)
    }

    @Test func refusesNonCalendarAndTruncatedBodies() {
        #expect(throws: ICalendarError.notICalendar) { try ICalendarParser.parse("<html><body>Sign in</body></html>", timeZone: dublin) }
        #expect(throws: ICalendarError.truncated) {
            try ICalendarParser.parse("BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:a\r\nEND:VEVENT\r\n", timeZone: dublin)
        }
        #expect(throws: ICalendarError.notText) { try ICalendarParser.parse(Data([0xFF, 0xFE, 0xFD]), timeZone: dublin) }
    }

    @Test func emptyTextPropertiesReadAsNil() throws {
        let calendar = try ICalendarParser.parse(wrap("BEGIN:VEVENT\r\nUID:a\r\nSUMMARY:\r\nLOCATION:   \r\nEND:VEVENT\r\n"), timeZone: dublin)
        #expect(calendar.events[0].summary == nil)
        #expect(calendar.events[0].location == nil)
    }
}
