import EagarCalendar
import EagarCore
import Foundation
import Testing
@testable import EagarPeople

struct InteractionInferenceTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let day: TimeInterval = 86_400

    private func person(optIn: Bool = false, last: Date? = nil) -> PersonSnapshot {
        PersonSnapshot(displayName: "Aoife", emailAddresses: ["aoife@example.ie"], lastInteractionAt: last, workSignalsOptIn: optIn)
    }

    private func event(_ id: String, endsDaysAgo: Double, attendees: [String], dataClass: DataClass) -> ClassifiedEvent {
        let end = now - endsDaysAgo * day
        return ClassifiedEvent(
            event: CalendarEvent(id: id, calendarID: "c", title: "Synthetic", start: end - 3600, end: end, attendeeEmails: attendees),
            dataClass: dataClass
        )
    }

    @Test func calendarMailAndLogsAllCount() {
        let p = person()
        let signals = InteractionInferrer.signals(
            for: p,
            events: [event("e1", endsDaysAgo: 20, attendees: ["Aoife@example.ie", "mark@example.ie"], dataClass: .personal)],
            mail: [MailContactSignal(addresses: ["aoife@example.ie"], date: now - 10 * day, dataClass: .personal)],
            logs: [ContactLogSnapshot(personID: p.id, occurredAt: now - 5 * day)],
            now: now
        )
        #expect(signals.map(\.kind) == [.calendarEvent, .mail, .manualLog])
        let inference = InteractionInferrer.infer(person: p, signals: signals)
        #expect(inference.personalLatest == now - 5 * day)
        #expect(inference.effectiveLatest == now - 5 * day)
        #expect(inference.effectiveClass == .personal)
    }

    @Test func futureAndUnrelatedSignalsAreIgnored() {
        let p = person()
        let signals = InteractionInferrer.signals(
            for: p,
            events: [
                event("future", endsDaysAgo: -1, attendees: ["aoife@example.ie"], dataClass: .personal),
                event("other", endsDaysAgo: 3, attendees: ["sean@example.ie"], dataClass: .personal),
            ],
            mail: [MailContactSignal(addresses: ["sean@example.ie"], date: now - day, dataClass: .personal)],
            logs: [ContactLogSnapshot(personID: UUID(), occurredAt: now - day)],
            now: now
        )
        #expect(signals.isEmpty)
    }

    @Test func storedPersonalDateIsUsedWhenNewer() {
        let p = person(last: now - day)
        let inference = InteractionInferrer.infer(person: p, signals: [InteractionSignal(date: now - 9 * day, kind: .mail, dataClass: .personal)])
        #expect(inference.personalLatest == now - day)
        #expect(inference.effectiveLatest == now - day)
    }

    @Test func noSignalsMeansNoDate() {
        let inference = InteractionInferrer.infer(person: person(), signals: [])
        #expect(inference.personalLatest == nil && inference.effectiveLatest == nil)
        #expect(inference.effectiveClass == .personal)
    }

    /// FR-PEOPLE-03, BD-26: work-lane signals are excluded unless Mark opts the person in.
    @Test func Boundary_collegeSignalsIgnoredWithoutOptIn() {
        let p = person(optIn: false)
        let signals = [
            InteractionSignal(date: now - 30 * day, kind: .mail, dataClass: .personal),
            InteractionSignal(date: now - day, kind: .mail, dataClass: .college),
        ]
        let inference = InteractionInferrer.infer(person: p, signals: signals)
        #expect(inference.effectiveLatest == now - 30 * day)
        #expect(inference.effectiveClass == .personal)
        #expect(inference.ignoredCollegeSignals == 1)
    }

    /// The taint rule over every counted signal (FR-CORE-03).
    @Test(arguments: [
        ([DataClass.personal], DataClass.personal),
        ([.personal, .college], .college),
        ([.college], .college),
        ([.publicContent, .approvedProfile], .personal),
    ])
    func Derivation_keepInTouchInteraction(classes: [DataClass], expected: DataClass) {
        let p = person(optIn: true)
        let signals = classes.enumerated().map { index, dataClass in
            InteractionSignal(date: now - Double(index + 1) * day, kind: .mail, dataClass: dataClass)
        }
        #expect(InteractionInferrer.infer(person: p, signals: signals).effectiveClass == expected)
    }

    /// An older college signal still taints the result: the newer personal date won only
    /// because no college date beat it.
    @Test func olderCollegeSignalStillTaints() {
        let p = person(optIn: true)
        let inference = InteractionInferrer.infer(person: p, signals: [
            InteractionSignal(date: now - day, kind: .manualLog, dataClass: .personal),
            InteractionSignal(date: now - 40 * day, kind: .calendarEvent, dataClass: .college),
        ])
        #expect(inference.effectiveLatest == now - day)
        #expect(inference.effectiveClass == .college)
    }

    /// The college-derived date never reaches the synced Person record.
    @Test func Boundary_collegeDerivedDateIsNeverStoredOnPerson() {
        let model = Person(displayName: "Aoife", emailAddresses: ["aoife@example.ie"], createdAt: now - 100 * day)
        model.workSignalsOptIn = true
        let inference = InteractionInferrer.infer(
            people: [model.snapshot],
            events: [event("crit", endsDaysAgo: 1, attendees: ["aoife@example.ie"], dataClass: .college)],
            mail: [MailContactSignal(addresses: ["aoife@example.ie"], date: now - 20 * day, dataClass: .personal)],
            logs: [],
            now: now
        )[model.personUUID]!
        #expect(inference.effectiveLatest == now - day)
        #expect(inference.effectiveClass == .college)
        model.apply(inference)
        #expect(model.lastInteractionAt == now - 20 * day)
        #expect(model.dataClass == .personal)
    }

    @Test func applyIgnoresAnotherPersonsInference() {
        let model = Person(displayName: "x", createdAt: now)
        model.apply(InteractionInference(personID: UUID(), personalLatest: now, effectiveLatest: now, effectiveClass: .personal, countedSignals: 1, ignoredCollegeSignals: 0))
        #expect(model.lastInteractionAt == nil)
    }

    @Test func personWithoutEmailsStillGetsManualLogs() {
        let p = PersonSnapshot(displayName: "Gran")
        let signals = InteractionInferrer.signals(
            for: p, events: [event("e", endsDaysAgo: 1, attendees: [], dataClass: .personal)], mail: [],
            logs: [ContactLogSnapshot(personID: p.id, occurredAt: now - day)], now: now
        )
        #expect(signals.map(\.kind) == [.manualLog])
    }
}
