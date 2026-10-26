import EagarCalendar
import EagarCore
import Foundation
import Testing
@testable import EagarPeople

struct NudgePlannerTests {
    typealias F = NudgeFixtures
    let calendar = NudgeFixtures.calendar

    private func plan(
        _ people: [PersonSnapshot], slots: [FreeSlot] = NudgeFixtures.freeEvenings(), now: Date = NudgeFixtures.weekStart,
        committed: Int = 0, budget: Int = 3, inferences: [UUID: InteractionInference] = [:], seed: UInt64 = 7
    ) -> [Nudge] {
        var rng = SeededGenerator(seed: seed)
        return NudgePlanner.plan(
            people: people, inferences: inferences, freeSlots: slots, week: F.week, now: now,
            alreadyCommitted: committed, settings: NudgePlannerSettings(weeklyBudget: budget), calendar: calendar, using: &rng
        )
    }

    private func overdue(_ name: String, daysAgo: Int, cadence: Int = 14, weekdays: Set<Int> = []) -> PersonSnapshot {
        PersonSnapshot(displayName: name, cadenceDays: cadence, preferredWeekdays: weekdays, lastInteractionAt: F.daysAgo(daysAgo))
    }

    @Test func neverMoreThanTheBudget() {
        let people = (0..<6).map { overdue("P\($0)", daysAgo: 30 + $0) }
        #expect(plan(people).count == 3)
        #expect(plan(people, committed: 2).count == 1)
        #expect(plan(people, committed: 5).isEmpty)
        #expect(plan(people, budget: 0).isEmpty)
    }

    @Test func defaultBudgetIsThree() {
        #expect(NudgePlannerSettings().weeklyBudget == 3)
    }

    @Test func overduePeopleComeFirstMostOverdueFirst() {
        let slight = overdue("Slight", daysAgo: 15)
        let far = overdue("Far", daysAgo: 60)
        let dueSoon = PersonSnapshot(displayName: "Soon", cadenceDays: 30, lastInteractionAt: F.daysAgo(26))
        let fresh = PersonSnapshot(displayName: "New")
        let nudges = plan([dueSoon, fresh, slight, far], budget: 2)
        #expect(nudges.map(\.displayName) == ["Far", "Slight"])
        #expect(nudges.allSatisfy { $0.isOverdue })
        #expect(plan([fresh, dueSoon], budget: 2).map(\.reason) == [.dueSoon, .noContactYet])
    }

    @Test func weekdayPreferenceIsRespected() throws {
        let thursdayOnly = overdue("Aoife", daysAgo: 49, weekdays: [5])
        let nudge = try #require(plan([thursdayOnly]).first)
        #expect(calendar.component(.weekday, from: nudge.slot.start) == 5)
        #expect(nudge.slot == DateInterval(start: F.at(3, 18), end: F.at(3, 22)))
        #expect(nudge.weeksSince == 7)
    }

    @Test func snoozeIsRespected() throws {
        var person = overdue("Seán", daysAgo: 40)
        person = PersonSnapshot(id: person.id, displayName: "Seán", cadenceDays: 14, lastInteractionAt: person.lastInteractionAt, snoozedUntil: F.at(5, 0))
        for seed in UInt64(0)..<20 {
            let nudge = try #require(plan([person], seed: seed).first)
            #expect(nudge.slot.start >= F.at(5, 0))
        }
        let snoozedPastWeek = PersonSnapshot(displayName: "x", cadenceDays: 14, lastInteractionAt: F.daysAgo(40), snoozedUntil: F.at(8, 0))
        #expect(plan([snoozedPastWeek]).isEmpty)
    }

    @Test func dueSoonStaysInsideTheCadenceWindow() throws {
        // Last seen 26 days before Monday, cadence 30: window is days 22...30 after it, so the part of this week inside it ends Friday 00:00.
        let person = PersonSnapshot(displayName: "Niamh", cadenceDays: 30, lastInteractionAt: F.daysAgo(26))
        for seed in UInt64(0)..<30 {
            let nudge = try #require(plan([person], seed: seed).first)
            #expect(nudge.reason == .dueSoon)
            #expect(nudge.slot.end <= F.at(4, 0))
        }
    }

    @Test func notYetInWindowGetsNothing() {
        let person = PersonSnapshot(displayName: "Ciarán", cadenceDays: 30, lastInteractionAt: F.daysAgo(5))
        #expect(plan([person]).isEmpty)
    }

    @Test func atMostOneNudgePerDay() {
        let a = overdue("A", daysAgo: 30, weekdays: [5])
        let b = overdue("B", daysAgo: 31, weekdays: [5])
        #expect(plan([a, b]).count == 1)
    }

    @Test func slotsOutsideSocialHoursOrTooShortAreIgnored() {
        let person = overdue("A", daysAgo: 30)
        let slots = [
            FreeSlot(interval: DateInterval(start: F.at(1, 1), end: F.at(1, 7)), dataClass: .personal),
            FreeSlot(interval: DateInterval(start: F.at(2, 18), end: F.at(2, 18, 45)), dataClass: .personal),
            FreeSlot(interval: DateInterval(start: F.at(3, 21, 30), end: F.at(4, 8)), dataClass: .personal),
        ]
        #expect(plan([person], slots: slots).isEmpty)
    }

    @Test func pastPartOfTheWeekIsIgnored() throws {
        let person = overdue("A", daysAgo: 30)
        let nudge = try #require(plan([person], now: F.at(6, 20)).first)
        #expect(nudge.slot == DateInterval(start: F.at(6, 20), end: F.at(6, 22)))
        #expect(plan([person], now: F.at(7, 0)).isEmpty)
    }

    @Test func sameSeedSamePlan() {
        let people = (0..<8).map { overdue("P\($0)", daysAgo: 20 + $0 * 3) }
        #expect(plan(people, seed: 42) == plan(people, seed: 42))
    }

    @Test func effectiveInferenceOverridesStoredDate() throws {
        let person = PersonSnapshot(displayName: "Aoife", cadenceDays: 30, lastInteractionAt: F.daysAgo(60))
        let inference = InteractionInference(personID: person.id, personalLatest: F.daysAgo(60), effectiveLatest: F.daysAgo(3), effectiveClass: .college, countedSignals: 1, ignoredCollegeSignals: 0)
        #expect(plan([person], inferences: [person.id: inference]).isEmpty)
    }

    /// The taint rule over person, free slot and inferred interaction (FR-CORE-03).
    @Test(arguments: [
        (DataClass.personal, DataClass.personal, DataClass.personal),
        (.college, .personal, .college),
        (.personal, .college, .college),
        (.publicContent, .personal, .personal),
    ])
    func Derivation_keepInTouchNudge(slotClass: DataClass, interactionClass: DataClass, expected: DataClass) throws {
        let person = overdue("Aoife", daysAgo: 30)
        let inference = InteractionInference(personID: person.id, personalLatest: nil, effectiveLatest: person.lastInteractionAt, effectiveClass: interactionClass, countedSignals: 1, ignoredCollegeSignals: 0)
        let nudge = try #require(plan([person], slots: F.freeEvenings(slotClass), inferences: [person.id: inference]).first)
        #expect(nudge.dataClass == expected)
    }

    @Test func consumesAvailabilityEngineSlots() throws {
        let events = [ClassifiedEvent(
            event: CalendarEvent(id: "crit", calendarID: "ncad", title: "Synthetic", start: F.at(0, 9), end: F.at(0, 18)),
            dataClass: .college
        )]
        let slots = AvailabilityEngine.freeSlots(for: events, in: DateInterval(start: F.at(0, 0), end: F.at(1, 0)), calendar: calendar)
        let nudge = try #require(plan([overdue("A", daysAgo: 30)], slots: slots).first)
        #expect(nudge.slot == DateInterval(start: F.at(0, 18), end: F.at(0, 22)))
        #expect(nudge.dataClass == .college, "the slot starts where a college event ends")
    }
}
