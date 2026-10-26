import EagarCalendar
import EagarCore
import EagarFeeds
import Foundation
import Testing
@testable import EagarBookings

private let source = SourceID()
private let extendURL = URL(string: "https://cdbooking.example/bookings/b_1/extend")!

private func loan(_ id: String = "b_1", due: Date, status: BookingStatus = .checkedOut, kind: BookingKind = .equipment, returnedAt: Date? = nil) -> BookingSnapshot {
    BookingSnapshot(sourceID: source, booking: BookingRecord(
        id: id, kind: kind, status: status, title: "Synthetic camera kit", location: "Returns desk",
        start: due.addingTimeInterval(-86400 * 2), due: kind == .equipment ? due : nil, returnedAt: returnedAt, extendURL: extendURL
    ))
}

/// FR-BOOK-03: return reminders at 24 h and 2 h, content-free for college (BD-04).
struct LoanReminderTests {
    let due = utcDate(2026, 10, 28, 16)

    @Test func plansTwentyFourAndTwoHoursBeforeDue() {
        let plan = LoanReminders.plan([loan(due: due)], now: fixtureNow, calendar: dublinCalendar)
        #expect(plan.map(\.fireDate) == [due.addingTimeInterval(-86400), due.addingTimeInterval(-7200)])
        #expect(plan.map(\.offsetMinutes) == [1440, 120])
        #expect(plan.last?.interruptionLevel == .timeSensitive)
        let deadlineID = FeedDeadline.deadlineID(origin: .booking, sourceID: source, externalID: "b_1")
        #expect(plan.first?.id == DeadlineNotificationPlan.identifier(deadlineID: deadlineID, offsetMinutes: 1440))
    }

    @Test func Boundary_B8_reminderContentIsFreeOfLoanDetails() {
        for note in LoanReminders.plan([loan(due: due)], now: fixtureNow, calendar: dublinCalendar) {
            for text in [note.title, note.body, note.threadIdentifier, note.id] {
                #expect(!text.contains("camera") && !text.contains("Returns desk") && !text.contains("b_1"))
            }
        }
    }

    @Test func offsetsAreConfigurable() {
        let plan = LoanReminders.plan([loan(due: due)], offsetsMinutes: [180, 30], now: fixtureNow, calendar: dublinCalendar)
        #expect(plan.map(\.offsetMinutes) == [180, 30])
    }

    @Test(arguments: [BookingStatus.returned, .approved, .requested, .cancelled])
    func onlyActiveLoansGetReminders(_ status: BookingStatus) {
        #expect(LoanReminders.plan([loan(due: due, status: status)], now: fixtureNow, calendar: dublinCalendar).isEmpty)
    }

    @Test func pastOffsetsAreSkipped() {
        let soon = fixtureNow.addingTimeInterval(3 * 3600)
        #expect(LoanReminders.plan([loan(due: soon)], now: fixtureNow, calendar: dublinCalendar).map(\.offsetMinutes) == [120])
    }

    @Test func deadlineMappingFollowsLoanState() {
        let open = LoanReminders.deadline(for: loan(due: due).booking, source: source)
        #expect(open?.origin == .booking && open?.isClosed == false && open?.dataClass == .college && open?.dueAt == due)
        #expect(LoanReminders.deadline(for: loan(due: due, status: .returned).booking, source: source)?.isClosed == true)
        #expect(LoanReminders.deadline(for: loan(due: due, status: .approved).booking, source: source) == nil)
        #expect(LoanReminders.deadline(for: loan(due: due, kind: .room).booking, source: source) == nil)
    }
}

/// FR-BOOK-04: clash with calendar busy time and an earlier return slot (PRD M2 acceptance criterion 3).
struct ReturnClashTests {
    let due = utcDate(2026, 10, 28, 16)

    private func busy(_ intervals: [(Date, Date)], dataClass: DataClass = .college) -> [BusyBlock] {
        let events = intervals.enumerated().map { index, pair in
            ClassifiedEvent(event: CalendarEvent(id: "e\(index)", calendarID: "c", title: "Synthetic class", start: pair.0, end: pair.1), dataClass: dataClass)
        }
        let window = DateInterval(start: due.addingTimeInterval(-3 * 86400), end: due.addingTimeInterval(86400))
        return AvailabilityEngine.busyBlocks(for: events, in: window, calendar: dublinCalendar)
    }

    @Test func teachingOverTheDueTimeProposesTheLatestEarlierSlot() throws {
        let blocks = busy([(utcDate(2026, 10, 28, 14), utcDate(2026, 10, 28, 17)), (utcDate(2026, 10, 28, 12, 30), utcDate(2026, 10, 28, 13))])
        let clash = try #require(ReturnClashCheck.check(loan(due: due), busy: blocks, now: fixtureNow, calendar: dublinCalendar))
        #expect(clash.clashingIntervals == [DateInterval(start: utcDate(2026, 10, 28, 14), end: utcDate(2026, 10, 28, 17))])
        #expect(clash.proposedSlot == DateInterval(start: utcDate(2026, 10, 28, 13, 45), end: utcDate(2026, 10, 28, 14)))
        #expect(clash.extendURL == extendURL)
        #expect(clash.dataClass == .college)
        #expect(clash.bookingID == "b_1")
    }

    @Test(arguments: [
        (utcDate(2026, 10, 28, 16), utcDate(2026, 10, 28, 17)),        // starts exactly at the due time
        (utcDate(2026, 10, 28, 15), utcDate(2026, 10, 28, 15, 45)),   // ends exactly when the return window opens
        (utcDate(2026, 10, 28, 10), utcDate(2026, 10, 28, 11)),
    ])
    func busyTimeOutsideTheReturnWindowIsNoClash(_ interval: (Date, Date)) {
        #expect(ReturnClashCheck.check(loan(due: due), busy: busy([interval]), now: fixtureNow, calendar: dublinCalendar) == nil)
    }

    @Test func partialOverlapOfTheReturnWindowIsAClash() {
        let blocks = busy([(utcDate(2026, 10, 28, 15, 30), utcDate(2026, 10, 28, 15, 50))])
        #expect(ReturnClashCheck.check(loan(due: due), busy: blocks, now: fixtureNow, calendar: dublinCalendar) != nil)
    }

    @Test func noFreeSlotOffersTheExtensionPageOnly() throws {
        let blocks = busy([(utcDate(2026, 10, 27, 8), utcDate(2026, 10, 27, 18)), (utcDate(2026, 10, 28, 8), utcDate(2026, 10, 28, 18))])
        let clash = try #require(ReturnClashCheck.check(loan(due: due), busy: blocks, now: fixtureNow, calendar: dublinCalendar))
        #expect(clash.proposedSlot == nil)
        #expect(clash.extendURL == extendURL)
    }

    @Test func proposalsStayInsideDeskHours() throws {
        let early = utcDate(2026, 10, 28, 9, 10)
        let blocks = busy([(utcDate(2026, 10, 28, 8), utcDate(2026, 10, 28, 9, 30))])
        let clash = try #require(ReturnClashCheck.check(loan(due: early), busy: blocks, now: fixtureNow, calendar: dublinCalendar))
        // 09:00–09:10 on the 28th is busy; the desk closed at 17:00 the day before.
        #expect(clash.proposedSlot == DateInterval(start: utcDate(2026, 10, 27, 16, 45), end: utcDate(2026, 10, 27, 17)))
    }

    @Test func proposalsAreNeverInThePast() throws {
        let today = utcDate(2026, 10, 27, 10)
        let blocks = busy([(utcDate(2026, 10, 27, 9, 30), utcDate(2026, 10, 27, 10, 30))])
        let clash = try #require(ReturnClashCheck.check(loan(due: today), busy: blocks, now: fixtureNow, calendar: dublinCalendar))
        #expect(clash.proposedSlot == DateInterval(start: utcDate(2026, 10, 27, 9, 15), end: utcDate(2026, 10, 27, 9, 30)))

        let tooLate = fixtureNow.addingTimeInterval(20 * 60)
        let overdue = try #require(ReturnClashCheck.check(loan(due: utcDate(2026, 10, 27, 10)), busy: blocks, now: tooLate.addingTimeInterval(3600), calendar: dublinCalendar))
        #expect(overdue.proposedSlot == nil)
    }

    @Test func inactiveLoansAreNotChecked() {
        let blocks = busy([(utcDate(2026, 10, 28, 14), utcDate(2026, 10, 28, 17))])
        #expect(ReturnClashCheck.check(loan(due: due, status: .returned), busy: blocks, now: fixtureNow, calendar: dublinCalendar) == nil)
    }

    /// FR-CORE-03: the clash takes the most restrictive class of the loan and the busy time.
    @Test(arguments: [
        (DataClass.personal, DataClass.personal, DataClass.personal),
        (.personal, .college, .college),
        (.college, .personal, .college),
        (.publicContent, .approvedProfile, .approvedProfile),
    ])
    func Derivation_bookingReturnClash(_ c: (loan: DataClass, busy: DataClass, expected: DataClass)) throws {
        let blocks = busy([(utcDate(2026, 10, 28, 14), utcDate(2026, 10, 28, 17))], dataClass: c.busy)
        let clash = try #require(ReturnClashCheck.check(
            bookingID: "x", dueAt: due, loanClass: c.loan, extendURL: nil, busy: blocks, now: fixtureNow, calendar: dublinCalendar
        ))
        #expect(clash.dataClass == c.expected)
    }
}

/// FR-BOOK-07 (data side): due-day Live Activity decision, times and counts only.
struct LoanLiveActivityTests {
    @Test func showsOnTheDueDayWithCountsOnly() throws {
        let loans = [loan("a", due: utcDate(2026, 10, 27, 16)), loan("b", due: utcDate(2026, 10, 27, 11)), loan("c", due: utcDate(2026, 10, 28, 16))]
        let plan = try #require(LoanLiveActivityPlanner.plan(loans, now: fixtureNow, calendar: dublinCalendar))
        #expect(plan.activityID == "loans.2026-10-27")
        #expect(plan.content == LoanActivityContent(loansDueToday: 2, overdueCount: 0, nextDueAt: utcDate(2026, 10, 27, 11)))
        #expect(plan.staleDate == utcDate(2026, 10, 27, 11))
        #expect(plan.endDate == utcDate(2026, 10, 27, 17))
    }

    @Test func countsOverdueAndEndsAfterTheGrace() throws {
        let loans = [loan("a", due: utcDate(2026, 10, 27, 8, 30))]
        let plan = try #require(LoanLiveActivityPlanner.plan(loans, now: fixtureNow, calendar: dublinCalendar))
        #expect(plan.content.overdueCount == 1)
        #expect(plan.content.nextDueAt == utcDate(2026, 10, 27, 8, 30))
        #expect(LoanLiveActivityPlanner.plan(loans, now: utcDate(2026, 10, 27, 9, 31), calendar: dublinCalendar) == nil)
    }

    @Test func nothingDueTodayShowsNothing() {
        #expect(LoanLiveActivityPlanner.plan([loan(due: utcDate(2026, 10, 28, 16))], now: fixtureNow, calendar: dublinCalendar) == nil)
        #expect(LoanLiveActivityPlanner.plan([loan(due: utcDate(2026, 10, 27, 16), status: .returned)], now: fixtureNow, calendar: dublinCalendar) == nil)
        #expect(LoanLiveActivityPlanner.plan([], now: fixtureNow, calendar: dublinCalendar) == nil)
    }

    @Test func Boundary_B8_activityContentCarriesNoLoanDetails() throws {
        let plan = try #require(LoanLiveActivityPlanner.plan([loan(due: utcDate(2026, 10, 27, 16))], now: fixtureNow, calendar: dublinCalendar))
        let encoded = String(decoding: try JSONEncoder().encode(plan.content), as: UTF8.self)
        #expect(!encoded.contains("camera") && !encoded.contains("Returns") && !encoded.contains("b_1"))
        #expect(!plan.activityID.contains("b_1"))
    }
}
