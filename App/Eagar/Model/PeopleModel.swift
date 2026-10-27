import EagarBrief
import EagarCalendar
import EagarCore
import EagarPeople
import Foundation
import Observation

/// A person's editable fields (FR-PEOPLE-02).
struct PersonEditorDraft: Equatable, Identifiable {
    let id: UUID
    var displayName: String
    var cadenceDays: Int
    var preferredWeekdays: Set<Int>
    var notes: String
    var workSignalsOptIn: Bool
    let birthday: Birthday?
    let fromContact: Bool

    init(_ record: PersonRecord) {
        id = record.id
        displayName = record.snapshot.displayName
        cadenceDays = record.snapshot.cadenceDays
        preferredWeekdays = record.snapshot.preferredWeekdays
        notes = record.notes
        workSignalsOptIn = record.snapshot.workSignalsOptIn
        birthday = record.snapshot.birthday
        fromContact = record.contactIdentifier != nil
    }
}

/// A catch-up Mark planned from a nudge: counted against the week's budget until it starts
/// (`NudgeBudget`). Only an opaque person ID and a time are kept, locally.
struct PlannedCatchUp: Codable, Equatable {
    let personID: UUID
    let start: Date
}

/// Keep in touch (FR-PEOPLE-01..06): people, contact logs, inferred last interactions,
/// nudges within the weekly budget and birthday reminders.
@MainActor
@Observable
final class PeopleModel {
    private(set) var people: [PersonRecord] = []
    private(set) var logs: [ContactLogSnapshot] = []
    /// This week's proposed catch-ups. A nudge's class follows its slot: one after a college
    /// event is `college`, shown in the app and counted only elsewhere.
    private(set) var nudges: [Nudge] = []
    private(set) var inferences: [UUID: InteractionInference] = [:]
    var failure: PeopleFailure?
    var onChange: (() -> Void)?

    /// The weekly social-capacity budget (FR-PEOPLE-04).
    var weeklyBudget: Int {
        didSet {
            guard weeklyBudget != oldValue else { return }
            defaults.set(weeklyBudget, forKey: Self.budgetKey)
            planNudges()
            onChange?()
        }
    }

    private let services: AppServices
    private let planner: PlannerModel
    private let repository: PeopleRepository
    private let defaults: UserDefaults
    private let clock: any EagarClock
    private let calendar: Calendar
    private let log = EagarLog(.people)
    /// Calendar events for inference and free slots, kept in memory only.
    private var pastEvents: [ClassifiedEvent] = []
    private var weekEvents: [ClassifiedEvent] = []

    static let budgetKey = "people.weeklyBudget"
    static let plannedKey = "people.plannedCatchUps"
    /// How far back calendar events count as interactions.
    static let inferenceLookbackDays = 180

    init(services: AppServices, planner: PlannerModel, defaults: UserDefaults, clock: any EagarClock, calendar: Calendar) {
        self.services = services
        self.planner = planner
        repository = PeopleRepository(stores: services.stores)
        self.defaults = defaults
        self.clock = clock
        self.calendar = calendar
        weeklyBudget = defaults.object(forKey: Self.budgetKey) as? Int ?? NudgePlannerSettings().weeklyBudget
    }

    var now: Date { clock.now() }

    func person(_ id: UUID) -> PersonRecord? { people.first { $0.id == id } }

    /// People sorted by how overdue they are relative to their cadence, then by name.
    var sortedPeople: [PersonRecord] {
        people.sorted { lhs, rhs in
            let l = dueRatio(lhs), r = dueRatio(rhs)
            return l != r ? l > r : lhs.snapshot.displayName.localizedStandardCompare(rhs.snapshot.displayName) == .orderedAscending
        }
    }

    /// The latest interaction Eagar may show on this device (may be college-derived when the
    /// person's opt-in is on; never stored).
    func lastContact(_ person: PersonRecord) -> Date? {
        inferences[person.id]?.effectiveLatest ?? person.snapshot.lastInteractionAt
    }

    /// Whether the shown last contact comes from a college signal (the badge says so).
    func lastContactIsCollege(_ person: PersonRecord) -> Bool {
        inferences[person.id]?.effectiveClass == .college
    }

    func daysSinceContact(_ person: PersonRecord) -> Int? {
        lastContact(person).map { max(0, calendar.dateComponents([.day], from: $0, to: now).day ?? 0) }
    }

    func isDue(_ person: PersonRecord) -> Bool {
        guard let days = daysSinceContact(person) else { return true }
        return days >= person.snapshot.cadenceDays
    }

    private func dueRatio(_ person: PersonRecord) -> Double {
        guard let days = daysSinceContact(person) else { return 0.5 }
        return Double(days) / Double(max(1, person.snapshot.cadenceDays))
    }

    // MARK: Loading

    /// Launch, activation and calendar changes: records, inference, nudges and birthdays.
    func refresh() async {
        await load()
        await loadEvents()
        await infer()
        planNudges()
        await reconcileBirthdays()
    }

    func load() async {
        do {
            people = try await repository.people()
            logs = try await repository.logs()
        } catch {
            log.error("reading people failed: \(error)")
            failure = .read
        }
    }

    private var week: DateInterval {
        NudgeBudget.week(containing: now, calendar: calendar) ?? DateInterval(start: calendar.startOfDay(for: now), duration: 7 * 86_400)
    }

    private func loadEvents() async {
        let start = calendar.date(byAdding: .day, value: -Self.inferenceLookbackDays, to: now) ?? now
        pastEvents = await planner.classifiedEvents(in: DateInterval(start: start, end: now))
        weekEvents = await planner.classifiedEvents(in: week)
    }

    /// Infers last interactions (FR-PEOPLE-03). College calendar events count only for people
    /// whose work-signal opt-in is on; only the personal part is written back.
    private func infer() async {
        let snapshots = people.map(\.snapshot)
        let result = InteractionInferrer.infer(people: snapshots, events: pastEvents, mail: [], logs: logs, now: now)
        inferences = result
        do {
            try await repository.apply(result)
            people = try await repository.people()
        } catch {
            log.error("saving inferred interactions failed: \(StoreFailureKind(error))")
        }
    }

    // MARK: Nudges (FR-PEOPLE-04, 05)

    /// Catch-ups planned from nudges that still count against this week's budget.
    var plannedCatchUps: [PlannedCatchUp] {
        guard let data = defaults.data(forKey: Self.plannedKey) else { return [] }
        do {
            return try JSONDecoder().decode([PlannedCatchUp].self, from: data)
        } catch {
            log.error("planned catch-ups unreadable; starting again")
            defaults.removeObject(forKey: Self.plannedKey)
            return []
        }
    }

    private func setPlannedCatchUps(_ items: [PlannedCatchUp]) {
        do {
            defaults.set(try JSONEncoder().encode(items), forKey: Self.plannedKey)
        } catch {
            log.error("planned catch-ups could not be saved")
        }
    }

    /// Logged contacts this week plus planned catch-ups not yet started (NudgeBudget).
    var alreadyCommitted: Int {
        let week = week
        let now = now
        let planned = plannedCatchUps.filter { week.contains($0.start) && $0.start >= now }.count
        return NudgeBudget.loggedContacts(logs, in: week) + planned
    }

    var budgetLeft: Int { max(0, weeklyBudget - alreadyCommitted) }

    /// Plans this week's nudges in real free slots. The generator is seeded with the week, so
    /// the proposals stay put while nothing changes.
    func planNudges() {
        let week = week
        let free = AvailabilityEngine.freeSlots(for: weekEvents, in: week, calendar: calendar)
        var generator = SeededGenerator(seed: UInt64(max(0, week.start.timeIntervalSince1970)))
        nudges = NudgePlanner.plan(
            people: people.map(\.snapshot), inferences: inferences, freeSlots: free, week: week, now: now,
            alreadyCommitted: alreadyCommitted, settings: NudgePlannerSettings(weeklyBudget: weeklyBudget),
            calendar: calendar, using: &generator
        )
    }

    /// Nudges for the brief, with their deterministic phrasing ("Thursday evening is free;
    /// Aoife: 7 weeks").
    var briefNudges: [BriefNudge] {
        nudges.map { BriefNudge(id: $0.id, title: NudgePhrasing.text(for: $0, calendar: calendar), slot: $0.slot, dataClass: $0.dataClass) }
    }

    func nudge(_ id: String) -> Nudge? { nudges.first { $0.id == id } }

    /// Applies a nudge action (FR-PEOPLE-05). Returns false when it could not be done.
    @discardableResult
    func perform(_ action: NudgeAction, on nudge: Nudge) async -> Bool {
        let effect = NudgeActions.effect(of: action, for: nudge, now: now, calendar: calendar)
        if let draft = effect.eventDraft {
            guard await writeCatchUp(draft, eventClass: effect.eventClass ?? nudge.dataClass) else { return false }
            setPlannedCatchUps(plannedCatchUps.filter { $0.start >= week.start } + [PlannedCatchUp(personID: nudge.personID, start: draft.start)])
        }
        if let log = effect.contactLog {
            do {
                try await repository.log(log, now: now)
            } catch {
                self.log.error("logging contact failed: \(StoreFailureKind(error))")
                failure = .save
                return false
            }
        }
        if effect.snoozedUntil != nil || effect.cadenceDays != nil {
            do {
                try await repository.update(nudge.personID) { $0.apply(effect) }
            } catch {
                log.error("updating a person failed: \(StoreFailureKind(error))")
                failure = .save
                return false
            }
        }
        await changed()
        return true
    }

    /// Writes the catch-up through the calendar write guard (FR-CAL-04). A college-class
    /// nudge (its slot follows a college event) can only go into a college calendar.
    private func writeCatchUp(_ draft: EventDraft, eventClass: DataClass) async -> Bool {
        let candidates = planner.modifiableEventCalendars.compactMap { calendar -> (CalendarInfo, CalendarTag)? in
            guard let tag = planner.tags[calendar.id], tag.confirmed else { return nil }
            return (calendar, tag)
        }
        let target = eventClass == .college
            ? candidates.first { $0.1.dataClass == .college }
            : candidates.first { $0.1.dataClass != .college } ?? candidates.first
        guard let (calendarInfo, tag) = target else {
            failure = .noCalendar
            return false
        }
        do {
            _ = try await CalendarWriter(store: services.eventStore).save(draft, derivedFrom: [eventClass], to: calendarInfo, tag: tag)
        } catch {
            log.error("writing a catch-up failed: \(error)")
            failure = .calendarWrite
            return false
        }
        await planner.refresh()
        return true
    }

    // MARK: People (FR-PEOPLE-01, 02, 03)

    /// Adds or updates people from picked contacts. Never reads notes (ContactImport has none).
    func add(_ contacts: [ContactImport]) async {
        for contact in contacts {
            do {
                _ = try await repository.upsert(contact, now: now)
            } catch {
                log.error("adding a person failed: \(StoreFailureKind(error))")
                failure = .save
            }
        }
        await changed()
    }

    /// Adds someone by name, without a contact.
    @discardableResult
    func add(name: String) async -> UUID? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            let id = try await repository.insert(name: trimmed, now: now)
            await changed()
            return id
        } catch {
            log.error("adding a person failed: \(StoreFailureKind(error))")
            failure = .save
            return nil
        }
    }

    func save(_ draft: PersonEditorDraft) async -> Bool {
        let name = draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        do {
            try await repository.update(draft.id) { person in
                person.displayName = name
                person.setCadence(days: draft.cadenceDays)
                person.setPreferredWeekdays(Array(draft.preferredWeekdays))
                person.relationshipNotes = draft.notes
                person.workSignalsOptIn = draft.workSignalsOptIn
            }
        } catch {
            log.error("saving a person failed: \(StoreFailureKind(error))")
            failure = .save
            return false
        }
        await changed()
        return true
    }

    func delete(_ id: UUID) async {
        do {
            try await repository.delete(id)
        } catch {
            log.error("deleting a person failed: \(StoreFailureKind(error))")
            failure = .save
        }
        await changed()
    }

    /// "We talked" (FR-PEOPLE-03): a manual, personal contact log.
    func logContact(_ personID: UUID, at date: Date? = nil, note: String = "") async {
        let draft = ContactLogDraft(personID: personID, occurredAt: min(date ?? now, now), kind: .manual, note: note)
        do {
            try await repository.log(draft, now: now)
        } catch {
            log.error("logging contact failed: \(StoreFailureKind(error))")
            failure = .save
        }
        await changed()
    }

    func logs(for personID: UUID) -> [ContactLogSnapshot] {
        logs.filter { $0.personID == personID }.sorted { $0.occurredAt > $1.occurredAt }
    }

    // MARK: Birthdays (FR-PEOPLE-06)

    func reconcileBirthdays() async {
        await BirthdayNotificationSync.sync(people: people.map(\.snapshot), now: now, scheduler: services.birthdayNotifications, calendar: calendar)
    }

    private func changed() async {
        await load()
        await infer()
        planNudges()
        await reconcileBirthdays()
        onChange?()
        await services.sync?.syncLocalChanges()
    }
}

/// SplitMix64: a small deterministic generator so a week's nudges don't jump about.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

/// User-facing keep-in-touch failures. Messages live in the String Catalog.
enum PeopleFailure: Identifiable, Equatable {
    case read, save, contacts, noCalendar, calendarWrite

    var id: Self { self }

    var message: LocalizedStringResource {
        switch self {
        case .read: "Eagar could not read your people."
        case .save: "Eagar could not save that change."
        case .contacts: "Eagar could not read the contacts you chose."
        case .noCalendar: "There is no calendar Eagar can add this catch-up to. Confirm a calendar's tag in Settings first."
        case .calendarWrite: "Eagar could not add the catch-up to your calendar."
        }
    }
}
