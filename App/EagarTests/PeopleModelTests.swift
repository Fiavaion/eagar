import EagarBrief
import EagarCalendar
import EagarCore
import EagarMoney
import EagarPeople
import EagarStore
import Foundation
import Synchronization
import Testing
@testable import Eagar

private struct FixedClock: EagarClock {
    let date: Date
    func now() -> Date { date }
}

/// A clock a test can move forward.
private final class MovableClock: EagarClock {
    private let date: Mutex<Date>
    init(_ date: Date) { self.date = Mutex(date) }
    func now() -> Date { date.withLock { $0 } }
    func set(_ newDate: Date) { date.withLock { $0 = newDate } }
}

/// A people reader whose every read fails.
private struct FailingPeopleReader: PeopleReading {
    func people() async throws(StoreError) -> [PersonRecord] { throw .fetchFailed(.personal) }
    func logs() async throws(StoreError) -> [ContactLogSnapshot] { throw .fetchFailed(.personal) }
}

/// Records birthday notification calls.
final class SpyBirthdays: BirthdayNotificationScheduling {
    let pending = Mutex<[String: PlannedBirthdayNotification]>([:])
    let removed = Mutex<[String]>([])
    func pendingIdentifiers() async -> [String] { pending.withLock { Array($0.keys) } }
    func add(_ planned: PlannedBirthdayNotification) async throws { pending.withLock { $0[planned.id] = planned } }
    func remove(identifiers: [String]) async {
        removed.withLock { $0 += identifiers }
        pending.withLock { p in identifiers.forEach { p[$0] = nil } }
    }
}

/// Records widget snapshots.
private final class SpyWidgetSnapshots: WidgetPublishing {
    let published = Mutex<[WidgetSnapshot]>([])
    func publish(_ snapshot: WidgetSnapshot) { published.withLock { $0.append(snapshot) } }
}

/// Records every donation call, unfiltered.
private final class RecordingDonor: IntentDonating {
    let calls = Mutex(0)
    func donateAddedDeadline(_ snapshot: DeadlineSnapshot) { calls.withLock { $0 += 1 } }
    func withdrawDonations(for deadlineID: UUID) {}
}

/// Records the content of every brief notification.
private final class SpyBriefContent: BriefNotificationScheduling {
    let contents = Mutex<[BriefNotificationContent]>([])
    func pendingBriefIdentifiers() async -> [String] { [] }
    func schedule(_ content: BriefNotificationContent, at date: Date, identifier: String) async throws { contents.withLock { $0.append(content) } }
    func remove(identifiers: [String]) async {}
}

/// A week where the only calendar is a college one with a short event every morning, so
/// every free slot follows a college event and every nudge is college.
private final class CollegeWeekStore: EventStoreAdapting {
    let events: [CalendarEvent]
    let list = [CalendarInfo(id: "ncad", title: "NCAD", accountTitle: "demo@ncad.ie", sourceKind: .calDAV, entity: .event, allowsModification: true)]

    init(now: Date, calendar: Calendar) {
        let week = calendar.dateInterval(of: .weekOfYear, for: now)!
        events = (0..<7).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: week.start)!
            let start = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
            return CalendarEvent(id: "c\(offset)", calendarID: "ncad", title: "Committee", start: start, end: start.addingTimeInterval(1800))
        }
    }

    func access(for entity: CalendarEntity) -> CalendarAccess { .fullAccess }
    func requestFullAccess() async throws(CalendarError) -> Bool { true }
    func calendars(for entity: CalendarEntity) -> [CalendarInfo] { list.filter { $0.entity == entity } }
    func events(in interval: DateInterval, calendarIDs: Set<String>?) async throws(CalendarError) -> [CalendarEvent] {
        events.filter { $0.end > interval.start && $0.start < interval.end }
    }
    func saveEvent(_ draft: EventDraft, toCalendar calendarID: String) async throws(CalendarError) -> String { "x" }
    func saveReminder(_ draft: ReminderDraft, toList listID: String) async throws(CalendarError) -> String { "r" }
    func removeReminder(id: String) async throws(CalendarError) {}
}

@MainActor
struct PeopleModelTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        calendar.firstWeekday = 2
        return calendar
    }()
    /// Monday 26 October 2026, 07:00: the whole week is ahead.
    private var monday: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 26, hour: 7))! }
    private let birthdays = SpyBirthdays()
    private let widgets = SpyWidgetSnapshots()
    private let donor = RecordingDonor()
    private let briefs = SpyBriefContent()

    private func makeModel(
        store: (any EventStoreAdapting)? = nil, clock: (any EagarClock)? = nil, defaults: UserDefaults? = nil
    ) throws -> AppModel {
        let services = try AppServices.make(
            inMemory: true, secrets: MemorySecrets(),
            eventStore: store ?? DemoEventStore(now: monday, calendar: calendar, richWeek: true),
            deadlineNotifications: SpyDeadlineNotifications(), briefNotifications: briefs, donations: donor, widgets: widgets,
            trialReminders: SpyTrialReminders(), birthdayNotifications: birthdays, pendingImports: PendingTrialImportStore(directory: nil)
        )
        let defaults = defaults ?? UserDefaults(suiteName: "eagar.people.\(UUID().uuidString)")!
        var settings = BriefSettings()
        settings.phrasingMode = .off
        settings.save(to: defaults)
        defaults.set(true, forKey: PlannerModel.notificationsRequestedKey)
        return AppModel(services: services, defaults: defaults, clock: clock ?? FixedClock(date: monday), calendar: calendar)
    }

    /// Calendars confirmed, `count` people added and the brief built.
    private func readyModel(
        store: (any EventStoreAdapting)? = nil, count: Int, clock: (any EagarClock)? = nil, defaults: UserDefaults? = nil
    ) async throws -> AppModel {
        let model = try makeModel(store: store, clock: clock, defaults: defaults)
        await model.planner.loadCalendars()
        await model.planner.confirmProposedTags()
        await addPeople(model, count: count)
        await model.appBecameActive()
        return model
    }

    /// Every string and data value a defaults suite can see, to search for a stored identifier.
    private func storedText(_ defaults: UserDefaults) -> String {
        defaults.dictionaryRepresentation().values.compactMap { value in
            (value as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? (value as? String)
        }.joined()
    }

    /// FR-PEOPLE-04: a planned catch-up counts against its whole week, also once it has
    /// started, so planning three early in the week does not free the budget later on.
    @Test func FR_PEOPLE_04_plannedCatchUpsCountForTheWholeWeek() async throws {
        let clock = MovableClock(monday)
        let model = try await readyModel(count: 8, clock: clock)
        #expect(model.people.nudges.count == 3)
        for _ in 0..<3 {
            let nudge = try #require(model.people.nudges.first)
            #expect(await model.people.perform(.plan, on: nudge))
        }
        #expect(model.people.alreadyCommitted == 3)
        #expect(model.people.nudges.isEmpty)

        let week = try #require(calendar.dateInterval(of: .weekOfYear, for: monday))
        let latest = try #require(model.people.plannedCatchUps.map(\.start).max())
        let later = latest.addingTimeInterval(3600)
        try #require(later < week.end)
        clock.set(later)
        await model.people.refresh()
        #expect(model.people.alreadyCommitted == 3)
        #expect(model.people.budgetLeft == 0)
        #expect(model.people.nudges.isEmpty)
    }

    /// FR-PEOPLE-05: someone with a catch-up planned this week is not proposed again.
    @Test func FR_PEOPLE_05_plannedPersonIsNotProposedAgainThisWeek() async throws {
        let model = try await readyModel(count: 1)
        let nudge = try #require(model.people.nudges.first)
        #expect(await model.people.perform(.plan, on: nudge))
        #expect(model.people.budgetLeft == 2)
        #expect(!model.people.nudges.contains { $0.personID == nudge.personID })
    }

    /// Invariant 1, D-028: a catch-up planned from a college nudge counts against the budget
    /// but never reaches standard defaults (device and iCloud backup); a personal one is stored.
    /// Builds before the college fix wrote every planned catch-up, college ones included, to
    /// defaults; launch removes that key so none stays in backup.
    @Test func Boundary_legacyPlannedCatchUpsArePurgedOnLaunch() throws {
        let defaults = try #require(UserDefaults(suiteName: "eagar.people.\(UUID().uuidString)"))
        let legacy = [PlannedCatchUp(personID: UUID(), start: monday)]
        defaults.set(try JSONEncoder().encode(legacy), forKey: PeopleModel.legacyPlannedKey)
        _ = try makeModel(defaults: defaults)
        #expect(defaults.object(forKey: PeopleModel.legacyPlannedKey) == nil)
    }

    @Test func Boundary_collegePlannedCatchUpNeverPersistedToDefaults() async throws {
        let collegeDefaults = try #require(UserDefaults(suiteName: "eagar.people.\(UUID().uuidString)"))
        let college = try await readyModel(store: CollegeWeekStore(now: monday, calendar: calendar), count: 1, defaults: collegeDefaults)
        let collegeNudge = try #require(college.people.nudges.first)
        #expect(collegeNudge.dataClass == .college)
        #expect(await college.people.perform(.plan, on: collegeNudge))
        #expect(college.people.alreadyCommitted == 1)
        #expect(college.people.plannedCatchUps.map(\.personID) == [collegeNudge.personID])
        #expect(!storedText(collegeDefaults).contains(collegeNudge.personID.uuidString))

        let personalDefaults = try #require(UserDefaults(suiteName: "eagar.people.\(UUID().uuidString)"))
        let personal = try await readyModel(count: 8, defaults: personalDefaults)
        let personalNudge = try #require(personal.people.nudges.first { $0.dataClass == .personal })
        #expect(await personal.people.perform(.plan, on: personalNudge))
        let data = try #require(personalDefaults.data(forKey: PeopleModel.plannedKey))
        let stored = try JSONDecoder().decode([PlannedCatchUp].self, from: data)
        #expect(stored.map(\.personID) == [personalNudge.personID])
    }

    /// FR-PEOPLE-06: a failed read leaves every pending birthday reminder alone and shows the
    /// error, on refresh and after a change.
    @Test func FR_PEOPLE_06_failedReadKeepsBirthdayReminders() async throws {
        let model = try makeModel()
        await model.people.add([ContactImport(contactIdentifier: "x", displayName: "Niamh", birthday: Birthday(month: 11, day: 2))])
        let before = birthdays.pending.withLock { Set($0.keys) }
        #expect(before.count == 1)
        let id = try #require(model.people.people.first?.id)
        birthdays.removed.withLock { $0.removeAll() }

        let failing = PeopleModel(
            services: model.services, planner: model.planner, defaults: UserDefaults(suiteName: "eagar.people.\(UUID().uuidString)")!,
            clock: FixedClock(date: monday), calendar: calendar, reader: FailingPeopleReader()
        )
        await failing.refresh()
        #expect(failing.failure == .read)
        #expect(birthdays.removed.withLock { $0.isEmpty })

        await failing.logContact(id)
        #expect(birthdays.removed.withLock { $0.isEmpty })
        #expect(birthdays.pending.withLock { Set($0.keys) } == before)
    }

    private func addPeople(_ model: AppModel, count: Int) async {
        let contacts = (0..<count).map { ContactImport(contactIdentifier: "c\($0)", displayName: "Person \($0)", emailAddresses: ["p\($0)@example.ie"]) }
        await model.people.add(contacts)
    }

    /// FR-PEOPLE-04 end to end: with the demo calendar, nudges never exceed the weekly budget,
    /// and contacts logged this week count against it.
    @Test func FR_PEOPLE_04_budgetRespectedEndToEnd() async throws {
        let model = try makeModel()
        await model.planner.loadCalendars()
        await model.planner.confirmProposedTags()
        await addPeople(model, count: 8)
        await model.appBecameActive()
        #expect(model.people.nudges.count == 3)
        #expect(model.planner.brief?.sections.first { $0.kind == .keepInTouch }?.items.count == 3)

        let first = try #require(model.people.people.first)
        await model.people.logContact(first.id)
        #expect(model.people.alreadyCommitted == 1)
        #expect(model.people.nudges.count <= 2)

        model.people.weeklyBudget = 1
        #expect(model.people.nudges.count == 0)
    }

    @Test func nudgesLandInFreeSlots() async throws {
        let model = try makeModel()
        await model.planner.loadCalendars()
        await model.planner.confirmProposedTags()
        await addPeople(model, count: 3)
        await model.appBecameActive()
        let week = calendar.dateInterval(of: .weekOfYear, for: monday)!
        let events = await model.planner.classifiedEvents(in: week)
        for nudge in model.people.nudges {
            #expect(!events.contains { $0.event.availability == .busy && !$0.event.isAllDay && $0.event.start < nudge.slot.end && $0.event.end > nudge.slot.start })
        }
    }

    /// BD-04: a nudge whose slot follows a college event is college. It shows in the in-app
    /// brief, but the widget gets only a count, the brief notification only counts, and
    /// nothing is donated.
    @Test func Boundary_collegeSlotNudgesNeverReachNotificationsDonationsOrWidgets() async throws {
        let model = try makeModel(store: CollegeWeekStore(now: monday, calendar: calendar))
        await model.planner.loadCalendars()
        await model.planner.confirmProposedTags()
        await model.people.add([
            ContactImport(contactIdentifier: "a", displayName: "Aoife Ní Bhriain", emailAddresses: ["aoife@example.ie"]),
            ContactImport(contactIdentifier: "b", displayName: "Cian Ó Murchú", emailAddresses: ["cian@example.ie"]),
        ])
        await model.appBecameActive()
        let nudges = model.people.nudges
        #expect(!nudges.isEmpty)
        #expect(nudges.allSatisfy { $0.dataClass == .college })

        let section = try #require(model.planner.brief?.sections.first { $0.kind == .keepInTouch })
        #expect(section.items.allSatisfy { $0.dataClass == .college })

        let names = ["Aoife", "Cian"]
        let snapshot = try #require(widgets.published.withLock { $0.last })
        #expect(snapshot.collegeCount >= nudges.count)
        for name in names { #expect(!snapshot.lines.contains { $0.title.contains(name) }) }
        for content in briefs.contents.withLock({ $0 }) {
            for name in names { #expect(!content.title.contains(name) && !content.body.contains(name)) }
        }
        #expect(donor.calls.withLock { $0 } == 0)
    }

    /// FR-PEOPLE-03: a past calendar event with the person as attendee sets the last contact;
    /// a college-calendar meeting counts only with the opt-in and is never stored.
    @Test func FR_PEOPLE_03_inferenceRespectsCalendarClass() async throws {
        let model = try makeModel()
        await model.planner.loadCalendars()
        await model.planner.confirmProposedTags()
        await model.people.add([
            ContactImport(contactIdentifier: "aoife", displayName: "Aoife", emailAddresses: ["aoife@example.ie"]),
            ContactImport(contactIdentifier: "ciara", displayName: "Ciara", emailAddresses: ["ciara@example.ie"]),
        ])
        await model.people.refresh()
        let aoife = try #require(model.people.people.first { $0.snapshot.displayName == "Aoife" })
        #expect(aoife.snapshot.lastInteractionAt != nil) // personal "Coffee with Aoife"
        let ciara = try #require(model.people.people.first { $0.snapshot.displayName == "Ciara" })
        #expect(model.people.lastContact(ciara) == nil) // college meeting ignored without opt-in

        var draft = PersonEditorDraft(ciara)
        draft.workSignalsOptIn = true
        #expect(await model.people.save(draft))
        let updated = try #require(model.people.person(ciara.id))
        #expect(model.people.lastContact(updated) != nil)
        #expect(model.people.lastContactIsCollege(updated))
        #expect(updated.snapshot.lastInteractionAt == nil) // the college date is never stored
    }

    @Test func FR_PEOPLE_06_birthdaysAreReconciled() async throws {
        let model = try makeModel()
        await model.people.add([ContactImport(contactIdentifier: "x", displayName: "Niamh", birthday: Birthday(month: 11, day: 2))])
        #expect(birthdays.pending.withLock { $0.count } == 1)
        let id = try #require(model.people.people.first?.id)
        await model.people.delete(id)
        #expect(birthdays.pending.withLock { $0.isEmpty })
    }

    @Test func notesAreKeptAndManualLogsMoveLastContact() async throws {
        let model = try makeModel()
        let id = try #require(await model.people.add(name: "Darragh"))
        var draft = PersonEditorDraft(try #require(model.people.person(id)))
        draft.notes = "Lent me the tent"
        draft.cadenceDays = 14
        #expect(await model.people.save(draft))
        #expect(model.people.person(id)?.notes == "Lent me the tent")
        await model.people.logContact(id)
        #expect(model.people.person(id)?.snapshot.lastInteractionAt == monday)
        #expect(model.people.logs(for: id).count == 1)
    }
}

/// FR-OS-03: "Add a trial" and "Log contact" create records; people offered to Shortcuts are
/// never college.
@MainActor
struct KeepInTouchAndTrialIntentTests {
    private func services(trials: SpyTrialReminders) throws -> AppServices {
        try AppServices.make(
            inMemory: true, secrets: MemorySecrets(), eventStore: DemoEventStore(), deadlineNotifications: SpyDeadlineNotifications(),
            trialReminders: trials, birthdayNotifications: SpyBirthdays(), pendingImports: PendingTrialImportStore(directory: nil)
        )
    }

    @Test func FR_OS_03_addTrialCreatesATrialWithReminders() async throws {
        let reminders = SpyTrialReminders()
        let services = try services(trials: reminders)
        let now = Date()
        let draft = TrialDraft(service: "Streamly", price: 9.99, renewsAt: now.addingTimeInterval(20 * 86_400))
        try await AddTrialIntent.add(try #require(draft.confirmed()), services: services, now: now)
        let trials = try await TrialRepository(stores: services.stores).all()
        #expect(trials.map(\.service) == ["Streamly"])
        #expect(trials.first?.dataClass == .personal)
        #expect(!reminders.pending.withLock { $0.isEmpty })
    }

    @Test func FR_OS_03_logContactRecordsALog() async throws {
        let services = try services(trials: SpyTrialReminders())
        let repository = PeopleRepository(stores: services.stores)
        let id = try await repository.insert(name: "Niamh", now: Date())
        try await LogContactIntent.log(id, services: services, now: Date())
        #expect(try await repository.logs().map(\.personID) == [id])
        #expect(try await PersonEntityQuery.people(services).map(\.name) == ["Niamh"])
    }
}

@MainActor
struct PilotMetricsTests {
    @Test func FR_GOV_01_weeklyEntriesReplaceAndPersist() {
        let defaults = UserDefaults(suiteName: "eagar.pilot.\(UUID().uuidString)")!
        let now = Date()
        let model = PilotMetricsModel(defaults: defaults, clock: FixedClock(date: now), calendar: .current)
        model.record(week: model.lastWeekStart, minutes: 300, pickups: 90)
        model.record(week: model.lastWeekStart.addingTimeInterval(3600), minutes: 280, pickups: nil)
        #expect(model.entries.count == 1)
        #expect(model.entries.first?.minutes == 280)
        let reloaded = PilotMetricsModel(defaults: defaults, clock: FixedClock(date: now), calendar: .current)
        #expect(reloaded.entries == model.entries)
        #expect(reloaded.averageMinutes == 280)
    }
}
