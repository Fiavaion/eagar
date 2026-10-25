import EagarCalendar
import EagarCore
import Foundation
import Testing

private typealias F = AvailabilityFixtures

/// FR-CAL-03: time zones and both 2026 Irish DST changes (29 March forward, 25 October back).
struct AvailabilityTimeZoneTests {
    // MARK: Time zones

    @Test func FR_CAL_03_timedEventsCreatedInUTCGiveTheSameInstantsInEveryZone() {
        let events = [
            F.event("a", "2026-10-14T09:00:00Z", "2026-10-14T10:00:00Z"),
            F.event("b", "2026-10-14T13:00:00Z", "2026-10-14T14:30:00Z"),
        ]
        let expected = AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: F.utc)
        #expect(expected.map(\.date) == [F.at("2026-10-14T08:00:00Z"), F.at("2026-10-14T10:00:00Z"), F.at("2026-10-14T14:30:00Z")])
        #expect(AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: F.dublin) == expected)
        #expect(AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: F.newYork) == expected)
    }

    @Test func FR_CAL_03_allDayEventCreatedInUTCCoversWholeLocalDaysOfTheEvaluatingCalendar() {
        // UTC midnight to 23:59:59 on 14 October spans local 14 and 15 October in Dublin (UTC+1)
        // and local 13 and 14 October in New York (UTC-4).
        let window = F.window("2026-10-12T00:00:00Z", "2026-10-17T00:00:00Z")
        let leave = F.event("leave", "2026-10-14T00:00:00Z", "2026-10-14T23:59:59Z", .busy, allDay: true)
        #expect(AvailabilityEngine.busyBlocks(for: [leave], in: window, calendar: F.dublin).map(\.interval) == [
            F.window("2026-10-13T23:00:00Z", "2026-10-15T23:00:00Z"),
        ])
        #expect(AvailabilityEngine.busyBlocks(for: [leave], in: window, calendar: F.newYork).map(\.interval) == [
            F.window("2026-10-13T04:00:00Z", "2026-10-15T04:00:00Z"),
        ])
    }

    @Test func FR_CAL_03_allDayEventCreatedAtLocalMidnightCoversOneLocalDay() {
        let window = F.window("2026-10-12T00:00:00Z", "2026-10-17T00:00:00Z")
        let dublinDay = F.event("leave", F.local(F.dublin, 2026, 10, 14), F.local(F.dublin, 2026, 10, 14, 23, 59, 59), .busy, allDay: true)
        #expect(AvailabilityEngine.busyBlocks(for: [dublinDay], in: window, calendar: F.dublin).map(\.interval) == [
            F.window("2026-10-13T23:00:00Z", "2026-10-14T23:00:00Z"),
        ])
        let newYorkDay = F.event("leave", F.local(F.newYork, 2026, 10, 14), F.local(F.newYork, 2026, 10, 15), .busy, allDay: true)
        #expect(AvailabilityEngine.busyBlocks(for: [newYorkDay], in: window, calendar: F.newYork).map(\.interval) == [
            F.window("2026-10-14T04:00:00Z", "2026-10-15T04:00:00Z"),
        ])
    }

    // MARK: Spring forward, 29 March 2026 (01:00 GMT becomes 02:00 IST)

    @Test func FR_CAL_03_allDayBusyOnSpringForwardDayInDublinIs23Hours() throws {
        let window = F.window("2026-03-28T12:00:00Z", "2026-03-30T12:00:00Z")
        let day = F.event("leave", F.local(F.dublin, 2026, 3, 29), F.local(F.dublin, 2026, 3, 29, 23, 59, 59), .busy, allDay: true)
        let blocks = AvailabilityEngine.busyBlocks(for: [day], in: window, calendar: F.dublin)
        let block = try #require(blocks.first)
        #expect(blocks.count == 1)
        #expect(block.interval == F.window("2026-03-29T00:00:00Z", "2026-03-29T23:00:00Z"))
        #expect(block.interval.duration == 23 * 3600)
        #expect(AvailabilityEngine.breakpoints(for: [day], in: window, calendar: F.dublin) == [
            Breakpoint(date: F.at("2026-03-28T12:00:00Z"), kind: .gapStart, dataClass: .publicContent),
            Breakpoint(date: F.at("2026-03-29T23:00:00Z"), kind: .eventEnd, dataClass: .personal),
        ])
    }

    @Test func FR_CAL_03_breakpointsAroundSpringForwardLandAtTheRightInstants() {
        // 00:30 to 01:30 GMT is local 00:30 GMT to 02:30 IST: one real hour.
        // 09:00 to 10:00 local on 30 March is 08:00 to 09:00 UTC (IST).
        let window = F.window("2026-03-29T00:00:00Z", "2026-03-30T12:00:00Z")
        let events = [
            F.event("night", "2026-03-29T00:30:00Z", "2026-03-29T01:30:00Z"),
            F.event("morning", F.local(F.dublin, 2026, 3, 30, 9), F.local(F.dublin, 2026, 3, 30, 10)),
        ]
        #expect(AvailabilityEngine.breakpoints(for: events, in: window, calendar: F.dublin).map(\.date) == [
            F.at("2026-03-29T00:00:00Z"), F.at("2026-03-29T01:30:00Z"), F.at("2026-03-30T09:00:00Z"),
        ])
    }

    // MARK: Fall back, 25 October 2026 (02:00 IST becomes 01:00 GMT)

    @Test func FR_CAL_03_allDayBusyOnFallBackDayInDublinIs25Hours() throws {
        let window = F.window("2026-10-24T12:00:00Z", "2026-10-26T12:00:00Z")
        let day = F.event("leave", F.local(F.dublin, 2026, 10, 25), F.local(F.dublin, 2026, 10, 25, 23, 59, 59), .unavailable, allDay: true)
        let blocks = AvailabilityEngine.busyBlocks(for: [day], in: window, calendar: F.dublin)
        let block = try #require(blocks.first)
        #expect(blocks.count == 1)
        #expect(block.interval == F.window("2026-10-24T23:00:00Z", "2026-10-26T00:00:00Z"))
        #expect(block.interval.duration == 25 * 3600)
        #expect(AvailabilityEngine.breakpoints(for: [day], in: window, calendar: F.dublin) == [
            Breakpoint(date: F.at("2026-10-24T12:00:00Z"), kind: .gapStart, dataClass: .publicContent),
            Breakpoint(date: F.at("2026-10-26T00:00:00Z"), kind: .eventEnd, dataClass: .personal),
        ])
    }

    @Test func FR_CAL_03_breakpointsAroundFallBackLandAtTheRightInstants() {
        // 00:30 to 01:30 UTC is local 01:30 IST to 01:30 GMT: one real hour, same wall-clock time.
        // 09:00 to 10:00 local on 26 October is 09:00 to 10:00 UTC (GMT).
        let window = F.window("2026-10-25T00:00:00Z", "2026-10-26T12:00:00Z")
        let events = [
            F.event("night", "2026-10-25T00:30:00Z", "2026-10-25T01:30:00Z"),
            F.event("morning", F.local(F.dublin, 2026, 10, 26, 9), F.local(F.dublin, 2026, 10, 26, 10)),
        ]
        let breakpoints = AvailabilityEngine.breakpoints(for: events, in: window, calendar: F.dublin)
        #expect(breakpoints.map(\.date) == [
            F.at("2026-10-25T00:00:00Z"), F.at("2026-10-25T01:30:00Z"), F.at("2026-10-26T10:00:00Z"),
        ])
        #expect(breakpoints.map(\.kind) == [.gapStart, .eventEnd, .eventEnd])
    }

    @Test func FR_CAL_03_dstDaysInNewYorkDifferFromDublin() {
        // America/New_York does not change on 25 October 2026 (it changes on 1 November): 24 hours.
        let window = F.window("2026-10-24T00:00:00Z", "2026-10-27T00:00:00Z")
        let day = F.event("leave", F.local(F.newYork, 2026, 10, 25), F.local(F.newYork, 2026, 10, 26), .busy, allDay: true)
        let blocks = AvailabilityEngine.busyBlocks(for: [day], in: window, calendar: F.newYork)
        #expect(blocks.map(\.interval.duration) == [24 * 3600])
    }
}
