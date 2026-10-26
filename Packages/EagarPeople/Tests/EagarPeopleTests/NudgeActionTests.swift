import EagarCore
import Foundation
import Testing
@testable import EagarPeople

struct NudgeActionTests {
    typealias F = NudgeFixtures
    let calendar = NudgeFixtures.calendar
    let personID = UUID()

    private func nudge(slot: DateInterval = DateInterval(start: NudgeFixtures.at(3, 18), end: NudgeFixtures.at(3, 22)), days: Int? = 49, dataClass: DataClass = .personal) -> Nudge {
        Nudge(personID: personID, displayName: "Aoife", slot: slot, reason: .overdue, daysSince: days, dataClass: dataClass)
    }

    @Test func planMakesAnEventInTheSlot() throws {
        let effect = NudgeActions.effect(of: .plan, for: nudge(dataClass: .college), now: F.weekStart, calendar: calendar)
        let draft = try #require(effect.eventDraft)
        #expect(draft.start == F.at(3, 18))
        #expect(draft.end == F.at(3, 19, 30))
        #expect(draft.title == "Catch up with Aoife")
        #expect(effect.eventClass == .college, "the write guard sees the nudge's class")
        #expect(effect.consumesBudget)
    }

    @Test func plannedEventNeverOverrunsTheSlot() throws {
        let short = DateInterval(start: F.at(3, 18), end: F.at(3, 19))
        let effect = NudgeActions.effect(of: .plan, for: nudge(slot: short), now: F.weekStart, calendar: calendar)
        #expect(effect.eventDraft?.end == F.at(3, 19))
    }

    @Test func logContactRecordsAPersonalLogAndClearsSnooze() throws {
        let person = Person(personUUID: personID, displayName: "Aoife", createdAt: F.daysAgo(100))
        person.snoozedUntil = F.at(6, 0)
        let effect = NudgeActions.effect(of: .logContact(at: F.at(1, 20), note: "Pints"), for: nudge(), now: F.at(2, 9), calendar: calendar)
        let draft = try #require(effect.contactLog)
        #expect(draft.kind == .nudge && draft.occurredAt == F.at(1, 20))
        let log = draft.makeLog(createdAt: F.at(2, 9))
        #expect(log.dataClass == .personal && log.note == "Pints" && log.personUUID == personID)
        person.apply(effect)
        #expect(person.lastInteractionAt == F.at(1, 20))
        #expect(person.snoozedUntil == nil)
        #expect(effect.consumesBudget)
    }

    @Test func logContactNeverLandsInTheFuture() {
        let effect = NudgeActions.effect(of: .logContact(at: F.at(5, 0)), for: nudge(), now: F.at(2, 9), calendar: calendar)
        #expect(effect.contactLog?.occurredAt == F.at(2, 9))
    }

    @Test func snoozeRunsToTheStartOfALaterDay() {
        let person = Person(personUUID: personID, displayName: "Aoife", createdAt: F.daysAgo(100))
        let effect = NudgeActions.effect(of: .snooze(days: 7), for: nudge(), now: F.at(1, 15), calendar: calendar)
        #expect(effect.snoozedUntil == F.at(8, 0))
        #expect(!effect.consumesBudget)
        person.apply(effect)
        #expect(person.snoozedUntil == F.at(8, 0))
        #expect(NudgeActions.effect(of: .snooze(days: 0), for: nudge(), now: F.at(1, 15), calendar: calendar).snoozedUntil == F.at(2, 0))
    }

    @Test func changeCadenceIsClamped() {
        let person = Person(personUUID: personID, displayName: "Aoife", createdAt: F.daysAgo(100))
        person.apply(NudgeActions.effect(of: .changeCadence(days: 21), for: nudge(), now: F.weekStart, calendar: calendar))
        #expect(person.cadenceDays == 21)
        person.apply(NudgeActions.effect(of: .changeCadence(days: -4), for: nudge(), now: F.weekStart, calendar: calendar))
        #expect(person.cadenceDays == minimumCadenceDays)
    }

    @Test func effectForAnotherPersonIsIgnored() {
        let person = Person(displayName: "Other", createdAt: F.daysAgo(100))
        person.apply(NudgeActions.effect(of: .changeCadence(days: 99), for: nudge(), now: F.weekStart, calendar: calendar))
        #expect(person.cadenceDays == defaultCadenceDays)
    }

    // MARK: Phrasing (FR-PEOPLE-05)

    @Test func briefLineReadsNaturally() {
        let locale = Locale(identifier: "en_IE")
        #expect(NudgePhrasing.text(for: nudge(), calendar: calendar, locale: locale) == "Thursday evening is free; Aoife: 7 weeks")
        let morning = nudge(slot: DateInterval(start: F.at(5, 10), end: F.at(5, 12)), days: 3)
        #expect(NudgePhrasing.text(for: morning, calendar: calendar, locale: locale) == "Saturday morning is free; Aoife: 3 days")
        let afternoon = nudge(slot: DateInterval(start: F.at(6, 14), end: F.at(6, 16)), days: nil)
        #expect(NudgePhrasing.text(for: afternoon, calendar: calendar, locale: locale) == "Sunday afternoon is free; Aoife: no contact yet")
    }

    @Test func singularUnits() {
        #expect(NudgePhrasing.sinceText(daysSince: 7, locale: Locale(identifier: "en_IE")) == "1 week")
        #expect(NudgePhrasing.sinceText(daysSince: 1, locale: Locale(identifier: "en_IE")) == "1 day")
    }
}
