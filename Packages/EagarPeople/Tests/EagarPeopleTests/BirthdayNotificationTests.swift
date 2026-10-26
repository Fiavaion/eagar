import EagarCore
import Foundation
import Synchronization
import Testing
@testable import EagarPeople

struct BirthdayNotificationTests {
    let calendar = NudgeFixtures.calendar

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    private func person(_ birthday: Birthday?, name: String = "Aoife", dataClass: DataClass = .personal) -> PersonSnapshot {
        PersonSnapshot(displayName: name, birthday: birthday, dataClass: dataClass)
    }

    @Test func nextBirthdayAtNineLocalWithAge() throws {
        let p = person(Birthday(month: 3, day: 17, year: 1990))
        let planned = try #require(BirthdayNotificationPlan.plan([p], now: date(2027, 1, 4), calendar: calendar).first)
        #expect(planned.fireDate == date(2027, 3, 17, 9))
        #expect(planned.id == "birthday.\(p.id.uuidString).2027")
        #expect(planned.title == "Aoife’s birthday")
        #expect(planned.body == "Turns 37 today")
    }

    @Test func missingYearLeavesAgeOut() throws {
        let planned = try #require(BirthdayNotificationPlan.plan([person(Birthday(month: 3, day: 17))], now: date(2027, 1, 4), calendar: calendar).first)
        #expect(planned.body == "Birthday today")
    }

    @Test func passedBirthdayRollsToNextYear() throws {
        let p = person(Birthday(month: 1, day: 2))
        let planned = try #require(BirthdayNotificationPlan.plan([p], now: date(2027, 1, 4), calendar: calendar).first)
        #expect(planned.fireDate == date(2028, 1, 2, 9))
    }

    @Test func birthdayTodayAfterFireTimeRollsOver() throws {
        let p = person(Birthday(month: 1, day: 4))
        #expect(BirthdayNotificationPlan.plan([p], now: date(2027, 1, 4, 8), calendar: calendar).first?.fireDate == date(2027, 1, 4, 9))
        #expect(BirthdayNotificationPlan.plan([p], now: date(2027, 1, 4, 10), calendar: calendar).first?.fireDate == date(2028, 1, 4, 9))
    }

    @Test func leapDayFallsOnTwentyEighthInCommonYears() throws {
        let p = person(Birthday(month: 2, day: 29, year: 2000))
        let common = try #require(BirthdayNotificationPlan.plan([p], now: date(2027, 1, 4), calendar: calendar).first)
        #expect(common.fireDate == date(2027, 2, 28, 9))
        #expect(common.body == "Turns 27 today")
        let leap = try #require(BirthdayNotificationPlan.plan([p], now: date(2028, 1, 4), calendar: calendar).first)
        #expect(leap.fireDate == date(2028, 2, 29, 9))
        let afterCommon = try #require(BirthdayNotificationPlan.plan([p], now: date(2027, 3, 1), calendar: calendar).first)
        #expect(afterCommon.fireDate == date(2028, 2, 29, 9))
    }

    @Test func birthYearInTheFutureOrSameYearHasNoAge() throws {
        let baby = try #require(BirthdayNotificationPlan.plan([person(Birthday(month: 6, day: 1, year: 2027))], now: date(2027, 1, 4), calendar: calendar).first)
        #expect(baby.body == "Birthday today")
    }

    @Test func peopleWithoutBirthdaysOrReadingAsCollegeAreSkipped() {
        let planned = BirthdayNotificationPlan.plan(
            [person(nil), person(Birthday(month: 5, day: 5), dataClass: .college)], now: date(2027, 1, 4), calendar: calendar
        )
        #expect(planned.isEmpty)
    }

    @Test func requestUsesLocalCalendarTrigger() throws {
        let planned = try #require(BirthdayNotificationPlan.plan([person(Birthday(month: 3, day: 17))], now: date(2027, 1, 4), calendar: calendar).first)
        let request = UserBirthdayNotificationScheduler.request(for: planned, calendar: calendar)
        #expect(request.identifier == planned.id)
        #expect(request.content.categoryIdentifier == "birthday")
    }

    // MARK: Reconciliation

    final class Spy: BirthdayNotificationScheduling {
        struct State {
            var pending: [String]
            var added: [String] = []
            var removed: [String] = []
        }
        let state: Mutex<State>
        init(pending: [String]) { state = Mutex(State(pending: pending)) }
        func pendingIdentifiers() async -> [String] { state.withLock { $0.pending } }
        func add(_ planned: PlannedBirthdayNotification) async throws { state.withLock { $0.added.append(planned.id) } }
        func remove(identifiers: [String]) async { state.withLock { $0.removed += identifiers } }
    }

    @Test func syncRemovesOnlyStaleBirthdays() async {
        let p = person(Birthday(month: 3, day: 17))
        let spy = Spy(pending: ["birthday.gone.2027", "deadline.x.60", "birthday.\(p.id.uuidString).2027"])
        await BirthdayNotificationSync.sync(people: [p], now: date(2027, 1, 4), scheduler: spy, calendar: calendar)
        let s = spy.state.withLock { $0 }
        #expect(s.removed == ["birthday.gone.2027"])
        #expect(s.added == ["birthday.\(p.id.uuidString).2027"])
    }
}
