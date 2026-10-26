import EagarCalendar
import EagarCore
import Foundation
import Testing
@testable import EagarPeople

/// Property-based tests for the nudge planner (PRD §10 M2: "nudges never exceed the weekly
/// budget; nudges land only in free slots; randomisation stays within cadence").
///
/// Each run generates a random week (busy events of mixed classes, people with random
/// cadences, last contacts, weekday preferences and snoozes, a random budget) from a seed.
/// The seed is in every failure message, so a failure reproduces exactly.
struct NudgePropertyTests {
    static let runs: UInt64 = 400
    let calendar = NudgeFixtures.calendar
    let week = NudgeFixtures.week

    struct Scenario {
        let now: Date
        let people: [PersonSnapshot]
        let freeSlots: [FreeSlot]
        let budget: Int
        let committed: Int
        let settings: NudgePlannerSettings
        let nudges: [Nudge]
    }

    private func scenario(seed: UInt64) -> Scenario {
        var rng = SeededGenerator(seed: seed)
        let hour: TimeInterval = 3600
        let now = week.start + Double(Int.random(in: 0..<(6 * 24), using: &rng)) * hour
        let events = (0..<Int.random(in: 0...14, using: &rng)).map { index -> ClassifiedEvent in
            let start = week.start + Double(Int.random(in: 0..<(7 * 48), using: &rng)) * 1800
            let end = start + Double(Int.random(in: 1...20, using: &rng)) * 1800
            return ClassifiedEvent(
                event: CalendarEvent(id: "e\(index)", calendarID: "c", title: "Synthetic", start: start, end: end),
                dataClass: Bool.random(using: &rng) ? .college : .personal
            )
        }
        let freeSlots = AvailabilityEngine.freeSlots(for: events, in: week, calendar: calendar)
        let people = (0..<Int.random(in: 0...10, using: &rng)).map { index -> PersonSnapshot in
            let cadence = Int.random(in: 1...90, using: &rng)
            let last: Date? = Int.random(in: 0..<5, using: &rng) == 0 ? nil
                : now - Double(Int.random(in: 0...(150 * 24), using: &rng)) * hour
            let weekdays: Set<Int> = Bool.random(using: &rng) ? [] : Set((1...7).filter { _ in Bool.random(using: &rng) })
            let snooze: Date? = Int.random(in: 0..<3, using: &rng) == 0
                ? week.start + Double(Int.random(in: -48...(9 * 24), using: &rng)) * hour : nil
            return PersonSnapshot(displayName: "Person \(index)", cadenceDays: cadence, preferredWeekdays: weekdays, lastInteractionAt: last, snoozedUntil: snooze)
        }
        let budget = Int.random(in: 0...5, using: &rng)
        let committed = Int.random(in: 0...3, using: &rng)
        let settings = NudgePlannerSettings(
            weeklyBudget: budget,
            minimumSlotMinutes: [30, 60, 90, 120].randomElement(using: &rng)!,
            cadenceWindowFraction: [0, 0.1, 0.25, 0.5, 1].randomElement(using: &rng)!
        )
        let nudges = NudgePlanner.plan(
            people: people, inferences: [:], freeSlots: freeSlots, week: week, now: now,
            alreadyCommitted: committed, settings: settings, calendar: calendar, using: &rng
        )
        return Scenario(now: now, people: people, freeSlots: freeSlots, budget: budget, committed: committed, settings: settings, nudges: nudges)
    }

    @Test func Property_nudgesNeverExceedTheWeeklyBudget() {
        for seed in 0..<Self.runs {
            let s = scenario(seed: seed)
            #expect(s.nudges.count <= max(0, s.budget - s.committed), "seed \(seed)")
            #expect(Set(s.nudges.map(\.personID)).count == s.nudges.count, "one nudge per person, seed \(seed)")
        }
    }

    @Test func Property_nudgesLandOnlyInFreeSlots() {
        for seed in 0..<Self.runs {
            let s = scenario(seed: seed)
            var days = Set<Date>()
            for nudge in s.nudges {
                #expect(s.freeSlots.contains { $0.interval.start <= nudge.slot.start && nudge.slot.end <= $0.interval.end }, "seed \(seed)")
                #expect(nudge.slot.start >= max(s.now, week.start) && nudge.slot.end <= week.end, "seed \(seed)")
                #expect(nudge.slot.duration >= TimeInterval(s.settings.minimumSlotMinutes * 60), "seed \(seed)")
                let day = calendar.startOfDay(for: nudge.slot.start)
                let open = calendar.date(bySettingHour: s.settings.dayStartHour, minute: 0, second: 0, of: day)!
                let close = calendar.date(bySettingHour: s.settings.dayEndHour, minute: 0, second: 0, of: day)!
                #expect(nudge.slot.start >= open && nudge.slot.end <= close, "social hours, seed \(seed)")
                #expect(days.insert(day).inserted, "one nudge per day, seed \(seed)")
            }
        }
    }

    @Test func Property_randomisedDatesStayWithinCadence() {
        for seed in 0..<Self.runs {
            let s = scenario(seed: seed)
            for nudge in s.nudges {
                let person = s.people.first { $0.id == nudge.personID }!
                guard let last = person.lastInteractionAt else {
                    #expect(nudge.reason == .noContactYet, "seed \(seed)")
                    continue
                }
                let cadence = person.cadenceDays
                let due = calendar.date(byAdding: .day, value: cadence, to: last)!
                if due <= max(s.now, week.start) {
                    #expect(nudge.reason == .overdue, "seed \(seed)")
                    continue
                }
                let lead = Int((Double(cadence) * s.settings.cadenceWindowFraction).rounded(.up))
                let earliest = calendar.date(byAdding: .day, value: max(min(1, cadence), cadence - lead), to: last)!
                #expect(nudge.reason == .dueSoon, "seed \(seed)")
                #expect(nudge.slot.start >= earliest, "not before the window, seed \(seed)")
                #expect(nudge.slot.end <= due, "not after the cadence runs out, seed \(seed)")
            }
        }
    }

    @Test func Property_weekdayPreferencesAndSnoozesAreRespected() {
        for seed in 0..<Self.runs {
            let s = scenario(seed: seed)
            for nudge in s.nudges {
                let person = s.people.first { $0.id == nudge.personID }!
                if !person.preferredWeekdays.isEmpty {
                    #expect(person.preferredWeekdays.contains(calendar.component(.weekday, from: nudge.slot.start)), "seed \(seed)")
                }
                if let snooze = person.snoozedUntil {
                    #expect(nudge.slot.start >= snooze, "seed \(seed)")
                }
            }
        }
    }

    /// The generator is not degenerate: across all runs, nudges are actually produced, in every
    /// reason, so the properties above are not vacuously true.
    @Test func generatorProducesNudges() {
        var reasons = Set<NudgeReason>()
        var total = 0
        for seed in 0..<Self.runs {
            let nudges = scenario(seed: seed).nudges
            total += nudges.count
            reasons.formUnion(nudges.map(\.reason))
        }
        #expect(total > Int(Self.runs) / 2)
        #expect(reasons == Set(NudgeReason.allCases))
    }
}
