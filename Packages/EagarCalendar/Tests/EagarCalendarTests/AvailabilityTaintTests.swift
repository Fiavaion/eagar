import EagarCalendar
import EagarCore
import Foundation
import Testing

private typealias F = AvailabilityFixtures

/// BD-03 taint rule for FR-CAL-03 derivations.
struct AvailabilityTaintTests {
    private let cal = F.dublin

    @Test("Busy blocks and their eventEnd take the most restrictive contributing class") func Derivation_calendarAvailability() {
        let events = [
            F.event("ncad", "2026-10-14T09:00:00Z", "2026-10-14T10:30:00Z", .busy, .college),
            F.event("dentist", "2026-10-14T10:00:00Z", "2026-10-14T11:00:00Z", .busy, .personal),
            F.event("podcast", "2026-10-14T14:00:00Z", "2026-10-14T15:00:00Z", .busy, .publicContent),
        ]
        let blocks = AvailabilityEngine.busyBlocks(for: events, in: F.day, calendar: cal)
        #expect(blocks.map(\.dataClass) == [
            Taint.derive(.calendarAvailability, from: [DataClass.college, .personal]),
            Taint.derive(.calendarAvailability, from: [DataClass.publicContent]),
        ])
        #expect(blocks.map(\.dataClass) == [.college, .publicContent])

        let ends = AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: cal).filter { $0.kind == .eventEnd }
        #expect(ends == [
            Breakpoint(date: F.at("2026-10-14T11:00:00Z"), kind: .eventEnd, dataClass: .college),
            Breakpoint(date: F.at("2026-10-14T15:00:00Z"), kind: .eventEnd, dataClass: .publicContent),
        ])
    }

    @Test func FR_CAL_03_conflictTakesTheMoreRestrictiveClass() {
        let events = [
            F.event("ncad", "2026-10-14T09:00:00Z", "2026-10-14T10:00:00Z", .busy, .college),
            F.event("dentist", "2026-10-14T09:30:00Z", "2026-10-14T10:30:00Z", .busy, .personal),
        ]
        #expect(AvailabilityEngine.conflicts(for: events, in: F.day, calendar: cal).map(\.dataClass) == [.college])
    }

    @Test func FR_CAL_03_freeSlotAfterACollegeBlockIsCollege() {
        let events = [
            F.event("ncad", "2026-10-14T09:00:00Z", "2026-10-14T10:00:00Z", .busy, .college),
            F.event("dentist", "2026-10-14T12:00:00Z", "2026-10-14T13:00:00Z", .busy, .personal),
        ]
        #expect(AvailabilityEngine.freeSlots(for: events, in: F.day, calendar: cal).map(\.dataClass) == [
            .publicContent, .college, .personal,
        ])
    }

    @Test func FR_CAL_03_gapAfterACollegeBlockGivesACollegeBreakpoint() {
        // The gap after the college block starts at its end, so the single breakpoint there is the
        // block's `.eventEnd`, which is college; the gap's free slot is college too.
        let events = [F.event("ncad", "2026-10-14T08:00:00Z", "2026-10-14T09:00:00Z", .busy, .college)]
        #expect(AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: cal) == [
            Breakpoint(date: F.at("2026-10-14T09:00:00Z"), kind: .eventEnd, dataClass: .college),
        ])
        #expect(AvailabilityEngine.freeSlots(for: events, in: F.day, calendar: cal, minimum: AvailabilityEngine.defaultMinimumGap).map(\.dataClass) == [.college])
    }

    @Test func FR_CAL_03_gapStartWithNoBlockBeforeItIsPublic() {
        let events = [F.event("ncad", "2026-10-14T12:00:00Z", "2026-10-14T13:00:00Z", .busy, .college)]
        let gapStarts = AvailabilityEngine.breakpoints(for: events, in: F.day, calendar: cal).filter { $0.kind == .gapStart }
        #expect(gapStarts == [Breakpoint(date: F.day.start, kind: .gapStart, dataClass: .publicContent)])
    }

    @Test func FR_CAL_03_collegeAllDayFreeEventDoesNotTaintAnything() {
        let events = [F.event("term", "2026-10-14T00:00:00Z", "2026-10-14T23:59:59Z", .free, allDay: true, .college)]
        #expect(AvailabilityEngine.freeSlots(for: events, in: F.day, calendar: cal).map(\.dataClass) == [.publicContent])
    }
}
