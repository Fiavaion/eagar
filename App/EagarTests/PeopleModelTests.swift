import EagarBrief
import EagarCalendar
import EagarCore
import EagarMoney
import EagarPeople
import Foundation
import Synchronization
import Testing
@testable import Eagar

private struct FixedClock: EagarClock {
    let date: Date
    func now() -> Date { date }
}

/// Records birthday notification calls.
final class SpyBirthdays: BirthdayNotificationScheduling {
    let pending = Mutex<[String: PlannedBirthdayNotification]>([:])
    func pendingIdentifiers() async -> [String] { pending.withLock { Array($0.keys) } }
    func add(_ planned: PlannedBirthdayNotification) async throws { pending.withLock { $0[planned.id] = planned } }
    func remove(identifiers: [String]) async { pending.withLock { p in identifiers.forEach { p[$0] = nil } } }
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

    private func makeModel(store: (any EventStoreAdapting)? = nil) throws -> AppModel {
        let services = try AppServices.make(
            inMemory: true, secrets: MemorySecrets(),
            eventStore: store ?? DemoEventStore(now: monday, calendar: calendar, richWeek: true),
            deadlineNotifications: SpyDeadlineNotifications(), briefNotifications: briefs, donations: donor, widgets: widgets,
            trialReminders: SpyTrialReminders(), birthdayNotifications: birthdays, pendingImports: PendingTrialImportStore(directory: nil)
        )
        let defaults = UserDefaults(suiteName: "eagar.people.\(UUID().uuidString)")!
        var settings = BriefSettings()
        settings.phrasingMode = .off
        settings.save(to: defaults)
        defaults.set(true, forKey: PlannerModel.notificationsRequestedKey)
        return AppModel(services: services, defaults: defaults, clock: FixedClock(date: monday), calendar: calendar)
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
