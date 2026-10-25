import EagarCalendar
import EagarCore
import Foundation
import Testing

private typealias F = AvailabilityFixtures

/// FR-CAL-03: free/busy, conflicts and breakpoints with fixture calendars.
struct AvailabilityTests {
    private let cal = F.utc

    // MARK: No events

    @Test func FR_CAL_03_noEventsGivesOneFreeSlotAndAGapStartAtWindowStart() {
        #expect(AvailabilityEngine.busyBlocks(for: [], in: F.day, calendar: cal).isEmpty)
        #expect(AvailabilityEngine.conflicts(for: [], in: F.day, calendar: cal).isEmpty)
        #expect(AvailabilityEngine.freeSlots(for: [], in: F.day, calendar: cal) == [FreeSlot(interval: F.day, dataClass: .publicContent)])
        #expect(AvailabilityEngine.breakpoints(for: [], in: F.day, calendar: cal) == [
            Breakpoint(date: F.day.start, kind: .gapStart, dataClass: .publicContent),
        ])
    }

    @Test func FR_CAL_03_zeroLengthWindowGivesNothing() {
        let window = DateInterval(start: F.day.start, duration: 0)
        let events = [F.event("a", "2026-10-14T07:00:00Z", "2026-10-14T09:00:00Z")]
        #expect(AvailabilityEngine.busyBlocks(for: events, in: window, calendar: cal).isEmpty)
        #expect(AvailabilityEngine.freeSlots(for: events, in: window, calendar: cal).isEmpty)
        #expect(AvailabilityEngine.breakpoints(for: events, in: window, calendar: cal).isEmpty)
    }

    // MARK: Single event

    @Test func FR_CAL_03_singleEvent() {
        let events = [F.event("a", "2026-10-14T10:00:00Z", "2026-10-14T11:00:00Z")]
        let blocks = AvailabilityEngine.busyBlocks(for: events, in: F.day, calendar: cal)
        #expect(blocks == [BusyBlock(interval: F.window("2026-10-14T10:00:00Z", "2026-10-14T11:00:00Z"), dataClass: .personal, eventIDs: ["a"])])
        #expect(AvailabilityEngine.freeSlots(for: events, in: F.day, calendar: cal).map(\.interval) == [
            F.window("2026-10-14T08:00:00Z", "2026-10-14T10:00:00Z"),
            F.window("2026-10-14T11:00:00Z", "2026-10-14T18:00:00Z"),
        ])
        #expect(AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: cal) == [
            Breakpoint(date: F.at("2026-10-14T08:00:00Z"), kind: .gapStart, dataClass: .publicContent),
            Breakpoint(date: F.at("2026-10-14T11:00:00Z"), kind: .eventEnd, dataClass: .personal),
        ])
    }

    // MARK: Merging

    @Test func FR_CAL_03_overlappingAndTouchingEventsMerge() {
        let events = [
            F.event("c", "2026-10-14T11:00:00Z", "2026-10-14T12:00:00Z"),  // touches b
            F.event("a", "2026-10-14T09:00:00Z", "2026-10-14T10:30:00Z"),
            F.event("b", "2026-10-14T10:00:00Z", "2026-10-14T11:00:00Z"),  // overlaps a
            F.event("d", "2026-10-14T09:15:00Z", "2026-10-14T09:45:00Z"),  // inside a
            F.event("e", "2026-10-14T14:00:00Z", "2026-10-14T15:00:00Z"),
        ]
        let blocks = AvailabilityEngine.busyBlocks(for: events, in: F.day, calendar: cal)
        #expect(blocks.map(\.interval) == [
            F.window("2026-10-14T09:00:00Z", "2026-10-14T12:00:00Z"),
            F.window("2026-10-14T14:00:00Z", "2026-10-14T15:00:00Z"),
        ])
        #expect(blocks.map(\.eventIDs) == [["a", "d", "b", "c"], ["e"]])
        #expect(AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: cal).map(\.date) == [
            F.at("2026-10-14T08:00:00Z"), F.at("2026-10-14T12:00:00Z"), F.at("2026-10-14T15:00:00Z"),
        ])
    }

    @Test func FR_CAL_03_duplicateEventIDIsListedOnce() {
        let event = F.event("a", "2026-10-14T09:00:00Z", "2026-10-14T10:00:00Z")
        let blocks = AvailabilityEngine.busyBlocks(for: [event, event], in: F.day, calendar: cal)
        #expect(blocks.map(\.eventIDs) == [["a"]])
        #expect(AvailabilityEngine.conflicts(for: [event, event], in: F.day, calendar: cal).isEmpty)
    }

    // MARK: Availability kinds

    @Test(arguments: [
        (EventAvailability.busy, true),
        (.tentative, true),
        (.unavailable, true),
        (.free, false),
        (.notSupported, false),
    ])
    func FR_CAL_03_timedEventBlocksByAvailability(availability: EventAvailability, blocks: Bool) {
        let events = [F.event("a", "2026-10-14T09:00:00Z", "2026-10-14T10:00:00Z", availability)]
        #expect(AvailabilityEngine.busyBlocks(for: events, in: F.day, calendar: cal).isEmpty == !blocks)
    }

    @Test func FR_CAL_03_tentativeBlocksButFreeDoesNot() {
        let events = [
            F.event("tentative", "2026-10-14T09:00:00Z", "2026-10-14T10:00:00Z", .tentative),
            F.event("free", "2026-10-14T12:00:00Z", "2026-10-14T13:00:00Z", .free),
        ]
        #expect(AvailabilityEngine.busyBlocks(for: events, in: F.day, calendar: cal).map(\.eventIDs) == [["tentative"]])
        #expect(AvailabilityEngine.freeSlots(for: events, in: F.day, calendar: cal).map(\.interval) == [
            F.window("2026-10-14T08:00:00Z", "2026-10-14T09:00:00Z"),
            F.window("2026-10-14T10:00:00Z", "2026-10-14T18:00:00Z"),
        ])
    }

    // MARK: All-day

    @Test(arguments: [
        (EventAvailability.busy, true),
        (.unavailable, true),
        (.tentative, false),
        (.free, false),
        (.notSupported, false),
    ])
    func FR_CAL_03_allDayEventBlocksOnlyWhenBusyOrUnavailable(availability: EventAvailability, blocks: Bool) {
        let events = [F.event("holiday", "2026-10-14T00:00:00Z", "2026-10-14T23:59:59Z", availability, allDay: true)]
        let result = AvailabilityEngine.busyBlocks(for: events, in: F.day, calendar: cal)
        #expect(result.isEmpty == !blocks)
    }

    @Test func FR_CAL_03_allDayFreeIsNotBusy() {
        let birthday = F.event("birthday", "2026-10-14T00:00:00Z", "2026-10-14T23:59:59Z", .free, allDay: true)
        #expect(AvailabilityEngine.freeSlots(for: [birthday], in: F.day, calendar: cal).map(\.interval) == [F.day])
    }

    @Test func FR_CAL_03_allDayBusyBlocksTheLocalDay() {
        let window = F.window("2026-10-13T12:00:00Z", "2026-10-15T12:00:00Z")
        let leave = F.event("leave", "2026-10-14T00:00:00Z", "2026-10-14T23:59:59Z", .busy, allDay: true)
        #expect(AvailabilityEngine.busyBlocks(for: [leave], in: window, calendar: cal).map(\.interval) == [
            F.window("2026-10-14T00:00:00Z", "2026-10-15T00:00:00Z"),
        ])
        // An end exactly at the next local midnight is exclusive: still one day.
        let exclusive = F.event("leave", "2026-10-14T00:00:00Z", "2026-10-15T00:00:00Z", .busy, allDay: true)
        #expect(AvailabilityEngine.busyBlocks(for: [exclusive], in: window, calendar: cal).map(\.interval) == [
            F.window("2026-10-14T00:00:00Z", "2026-10-15T00:00:00Z"),
        ])
    }

    // MARK: Multi-day and clipping

    @Test func FR_CAL_03_multiDayTimedEventIsClippedToTheWindow() {
        let events = [F.event("trip", "2026-10-13T20:00:00Z", "2026-10-16T10:00:00Z")]
        #expect(AvailabilityEngine.busyBlocks(for: events, in: F.day, calendar: cal).map(\.interval) == [F.day])
        #expect(AvailabilityEngine.freeSlots(for: events, in: F.day, calendar: cal).isEmpty)
        // The block ends at the window end, not at a real event end inside the window.
        #expect(AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: cal).isEmpty)
    }

    @Test func FR_CAL_03_multiDayAllDayEventIsClippedAndEndsAtLocalMidnight() {
        let window = F.window("2026-10-14T12:00:00Z", "2026-10-17T12:00:00Z")
        let conference = F.event("conference", "2026-10-13T00:00:00Z", "2026-10-15T23:59:59Z", .busy, allDay: true)
        #expect(AvailabilityEngine.busyBlocks(for: [conference], in: window, calendar: cal).map(\.interval) == [
            F.window("2026-10-14T12:00:00Z", "2026-10-16T00:00:00Z"),
        ])
        #expect(AvailabilityEngine.breakpoints(for: [conference], in: window, calendar: cal) == [
            Breakpoint(date: F.at("2026-10-16T00:00:00Z"), kind: .eventEnd, dataClass: .personal),
        ])
    }

    @Test func FR_CAL_03_eventsOutsideOrTouchingTheWindowEdgesAreIgnored() {
        let events = [
            F.event("before", "2026-10-14T07:00:00Z", "2026-10-14T08:00:00Z"),
            F.event("after", "2026-10-14T18:00:00Z", "2026-10-14T19:00:00Z"),
        ]
        #expect(AvailabilityEngine.busyBlocks(for: events, in: F.day, calendar: cal).isEmpty)
    }

    @Test func FR_CAL_03_eventEndingAtWindowEndGivesNoBreakpoint() {
        let events = [F.event("late", "2026-10-14T17:00:00Z", "2026-10-14T18:00:00Z")]
        #expect(AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: cal) == [
            Breakpoint(date: F.day.start, kind: .gapStart, dataClass: .publicContent),
        ])
    }

    // MARK: Defensive input

    @Test func FR_CAL_03_zeroLengthAndInvertedEventsAreIgnored() {
        let events = [
            F.event("zero", "2026-10-14T09:00:00Z", "2026-10-14T09:00:00Z"),
            F.event("inverted", "2026-10-14T11:00:00Z", "2026-10-14T10:00:00Z"),
            F.event("zeroAllDay", "2026-10-14T00:00:00Z", "2026-10-14T00:00:00Z", .busy, allDay: true),
            F.event("invertedAllDay", "2026-10-15T00:00:00Z", "2026-10-14T00:00:00Z", .busy, allDay: true),
        ]
        #expect(AvailabilityEngine.busyBlocks(for: events, in: F.day, calendar: cal).isEmpty)
        #expect(AvailabilityEngine.conflicts(for: events, in: F.day, calendar: cal).isEmpty)
        #expect(AvailabilityEngine.freeSlots(for: events, in: F.day, calendar: cal).map(\.interval) == [F.day])
    }

    // MARK: Gap threshold

    @Test func FR_CAL_03_gapOfExactlyFifteenMinutesCounts() {
        let events = [F.event("a", "2026-10-14T08:15:00Z", "2026-10-14T18:00:00Z")]
        #expect(AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: cal) == [
            Breakpoint(date: F.day.start, kind: .gapStart, dataClass: .publicContent),
        ])
        #expect(AvailabilityEngine.freeSlots(for: events, in: F.day, calendar: cal, minimum: AvailabilityEngine.defaultMinimumGap).count == 1)
    }

    @Test func FR_CAL_03_gapOfFourteenMinutesDoesNotCount() {
        let events = [F.event("a", "2026-10-14T08:14:00Z", "2026-10-14T18:00:00Z")]
        #expect(AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: cal).isEmpty)
        #expect(AvailabilityEngine.freeSlots(for: events, in: F.day, calendar: cal, minimum: AvailabilityEngine.defaultMinimumGap).isEmpty)
        #expect(AvailabilityEngine.freeSlots(for: events, in: F.day, calendar: cal).count == 1)
    }

    @Test func FR_CAL_03_eventEndThatStartsALongGapIsOneEventEndBreakpoint() {
        let events = [
            F.event("a", "2026-10-14T08:00:00Z", "2026-10-14T09:00:00Z"),
            F.event("b", "2026-10-14T10:00:00Z", "2026-10-14T10:30:00Z"),
            F.event("c", "2026-10-14T10:35:00Z", "2026-10-14T11:00:00Z"),
        ]
        let breakpoints = AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: cal)
        #expect(breakpoints == [
            Breakpoint(date: F.at("2026-10-14T09:00:00Z"), kind: .eventEnd, dataClass: .personal),
            Breakpoint(date: F.at("2026-10-14T10:30:00Z"), kind: .eventEnd, dataClass: .personal),
            Breakpoint(date: F.at("2026-10-14T11:00:00Z"), kind: .eventEnd, dataClass: .personal),
        ])
    }

    @Test func FR_CAL_03_customMinimumGap() {
        let events = [F.event("a", "2026-10-14T08:30:00Z", "2026-10-14T18:00:00Z")]
        #expect(AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: cal, minimumGap: 31 * 60).isEmpty)
        #expect(AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: cal, minimumGap: 30 * 60).count == 1)
    }

    // MARK: Conflicts

    @Test func FR_CAL_03_conflictsReportOverlappingPairsOnly() {
        let events = [
            F.event("a", "2026-10-14T09:00:00Z", "2026-10-14T12:00:00Z"),
            F.event("b", "2026-10-14T09:30:00Z", "2026-10-14T10:00:00Z"),
            F.event("c", "2026-10-14T11:00:00Z", "2026-10-14T13:00:00Z"),
            F.event("d", "2026-10-14T13:00:00Z", "2026-10-14T14:00:00Z"),  // touches c: no conflict
            F.event("e", "2026-10-14T11:30:00Z", "2026-10-14T11:45:00Z", .free),  // free: no conflict
        ]
        let conflicts = AvailabilityEngine.conflicts(for: events, in: F.day, calendar: cal)
        #expect(conflicts == [
            Conflict(eventIDs: ["a", "b"], overlap: F.window("2026-10-14T09:30:00Z", "2026-10-14T10:00:00Z"), dataClass: .personal),
            Conflict(eventIDs: ["a", "c"], overlap: F.window("2026-10-14T11:00:00Z", "2026-10-14T12:00:00Z"), dataClass: .personal),
        ])
    }

    @Test func FR_CAL_03_conflictsAreClippedAndIncludeAllDayBusy() {
        let events = [
            F.event("leave", "2026-10-14T00:00:00Z", "2026-10-14T23:59:59Z", .busy, allDay: true),
            F.event("meeting", "2026-10-14T07:00:00Z", "2026-10-14T09:00:00Z", .tentative),
        ]
        #expect(AvailabilityEngine.conflicts(for: events, in: F.day, calendar: cal) == [
            Conflict(eventIDs: ["leave", "meeting"], overlap: F.window("2026-10-14T08:00:00Z", "2026-10-14T09:00:00Z"), dataClass: .personal),
        ])
    }

    @Test func FR_CAL_03_conflictsAreOrderedByOverlapStartThenIDs() {
        let events = [
            F.event("z", "2026-10-14T09:00:00Z", "2026-10-14T10:00:00Z"),
            F.event("y", "2026-10-14T09:00:00Z", "2026-10-14T10:00:00Z"),
            F.event("x", "2026-10-14T09:00:00Z", "2026-10-14T10:00:00Z"),
        ]
        #expect(AvailabilityEngine.conflicts(for: events, in: F.day, calendar: cal).map(\.eventIDs) == [
            ["x", "y"], ["x", "z"], ["y", "z"],
        ])
    }
}
