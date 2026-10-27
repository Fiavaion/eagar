import EagarBrief
import EagarCalendar
import EagarCore
import EagarSuggest
import Foundation
import Synchronization
import Testing
@testable import Eagar

/// Regression tests for the M1 calendar/brief review findings (FR-BRIEF-02, FR-BRIEF-08,
/// FR-DL-02, FR-DL-03, FR-OS-05, NFR-REL-01, BD-04).
private struct FixedClock: EagarClock {
    let date: Date
    func now() -> Date { date }
}

/// Whether notifications are allowed, shared by both spies like the real notification centre.
private final class Authorisation: Sendable {
    let granted: Mutex<Bool>
    init(granted: Bool) { self.granted = Mutex(granted) }
}

private final class DeadlineSchedulerSpy: NotificationScheduling {
    let authorisation: Authorisation
    let pending = Mutex<[String: PlannedNotification]>([:])
    init(authorisation: Authorisation) { self.authorisation = authorisation }
    func pendingIdentifiers() async -> [String] { pending.withLock { Array($0.keys) } }
    func add(_ planned: PlannedNotification) async throws { pending.withLock { $0[planned.id] = planned } }
    func remove(identifiers: [String]) async { pending.withLock { p in identifiers.forEach { p[$0] = nil } } }
    func requestAuthorization() async throws -> Bool {
        authorisation.granted.withLock { $0 = true }
        return true
    }
}

/// Like `UserBriefNotificationScheduler`, adds nothing until notifications are allowed.
private final class BriefSchedulerSpy: BriefNotificationScheduling {
    let authorisation: Authorisation
    let scheduled = Mutex<[String: Date]>([:])
    init(authorisation: Authorisation) { self.authorisation = authorisation }
    func pendingBriefIdentifiers() async -> [String] { scheduled.withLock { Array($0.keys) } }
    func schedule(_ content: BriefNotificationContent, at date: Date, identifier: String) async throws {
        guard authorisation.granted.withLock({ $0 }) else { return }
        scheduled.withLock { $0[identifier] = date }
    }
    func remove(identifiers: [String]) async { scheduled.withLock { s in identifiers.forEach { s[$0] = nil } } }
}

private final class DonorSpy: IntentDonating {
    let donated = Mutex<[UUID]>([])
    let withdrawn = Mutex<[UUID]>([])
    func donateAddedDeadline(_ snapshot: DeadlineSnapshot) { donated.withLock { $0.append(snapshot.id) } }
    func withdrawDonations(for deadlineID: UUID) { withdrawn.withLock { $0.append(deadlineID) } }
}

/// The demo calendars and events, with reminders it records and removals that can be made to fail.
private final class ReminderStoreSpy: EventStoreAdapting {
    let demo: DemoEventStore
    let reminders = Mutex<[String: ReminderDraft]>([:])
    let failRemovals = Mutex(false)
    private let counter = Mutex(0)

    init(now: Date, calendar: Calendar) { demo = DemoEventStore(now: now, calendar: calendar) }

    func access(for entity: CalendarEntity) -> CalendarAccess { demo.access(for: entity) }
    func requestFullAccess() async throws(CalendarError) -> Bool { try await demo.requestFullAccess() }
    func calendars(for entity: CalendarEntity) -> [CalendarInfo] { demo.calendars(for: entity) }
    func events(in interval: DateInterval, calendarIDs: Set<String>?) async throws(CalendarError) -> [CalendarEvent] {
        try await demo.events(in: interval, calendarIDs: calendarIDs)
    }
    func saveEvent(_ draft: EventDraft, toCalendar calendarID: String) async throws(CalendarError) -> String {
        try await demo.saveEvent(draft, toCalendar: calendarID)
    }
    func saveReminder(_ draft: ReminderDraft, toList listID: String) async throws(CalendarError) -> String {
        let id = counter.withLock { $0 += 1; return "spy.reminder.\($0)" }
        reminders.withLock { $0[id] = draft }
        return id
    }
    func removeReminder(id: String) async throws(CalendarError) {
        if failRemovals.withLock({ $0 }) { throw .saveFailed }
        _ = reminders.withLock { $0.removeValue(forKey: id) }
    }
}

@MainActor
struct PlannerFixesTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return calendar
    }()
    private let donor = DonorSpy()

    private func at(_ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: hour, minute: minute))!
    }

    @MainActor
    private struct Harness {
        let model: AppModel
        let deadlines: DeadlineSchedulerSpy
        let briefs: BriefSchedulerSpy
        var planner: PlannerModel { model.planner }
    }

    private func makeHarness(
        at now: Date, authorised: Bool = true, eventStore: (any EventStoreAdapting)? = nil, settings: BriefSettings = BriefSettings()
    ) throws -> Harness {
        let authorisation = Authorisation(granted: authorised)
        let deadlines = DeadlineSchedulerSpy(authorisation: authorisation)
        let briefs = BriefSchedulerSpy(authorisation: authorisation)
        let services = try AppServices.make(
            inMemory: true, secrets: MemorySecrets(), eventStore: eventStore ?? DemoEventStore(now: now, calendar: calendar),
            deadlineNotifications: deadlines, briefNotifications: briefs, donations: donor
        )
        let defaults = UserDefaults(suiteName: "eagar.fixes.\(UUID().uuidString)")!
        var settings = settings
        settings.phrasingMode = .off
        settings.save(to: defaults)
        // The first save would otherwise ask for permission and reschedule; the tests that need
        // that call it explicitly.
        defaults.set(true, forKey: PlannerModel.notificationsRequestedKey)
        let model = AppModel(services: services, defaults: defaults, clock: FixedClock(date: now), calendar: calendar)
        return Harness(model: model, deadlines: deadlines, briefs: briefs)
    }

    private func save(_ planner: PlannerModel, title: String, due: Date, dataClass: DataClass = .personal, list: String? = nil, override: Bool = false) async throws -> DeadlineRow {
        var draft = planner.newDeadlineDraft()
        draft.title = title
        draft.dueAt = due
        draft.dataClass = dataClass
        draft.mirrorListID = list
        draft.mirrorOverride = override
        #expect(await planner.save(draft))
        return try #require(planner.deadlines.first { $0.snapshot.title == title })
    }

    // MARK: 1. Brief open is logged on cold launch (FR-BRIEF-08, SM2)

    @Test func openBeforeComposeIsLoggedAndTheBriefCompletes() async throws {
        let harness = try makeHarness(at: at(7))
        let planner = harness.planner
        // Cold launch: the Today tab appears before startup has composed the brief.
        await planner.briefOpened()
        await planner.refresh()
        let brief = try #require(planner.brief)
        #expect(!brief.allItems.isEmpty)
        for item in brief.allItems {
            await planner.perform(.dismiss, on: item)
        }
        let kinds = try await harness.model.services.eventLog.records().map(\.kind)
        #expect(kinds.filter { $0 == .briefOpened }.count == 1)
        #expect(kinds.contains(.briefCompleted))
    }

    @Test func composeThenOpenAlsoCompletes() async throws {
        let harness = try makeHarness(at: at(7))
        let planner = harness.planner
        await planner.refresh()
        await planner.briefOpened()
        for item in try #require(planner.brief).allItems {
            await planner.perform(.dismiss, on: item)
        }
        let kinds = try await harness.model.services.eventLog.records().map(\.kind)
        #expect(kinds.contains(.briefOpened))
        #expect(kinds.contains(.briefCompleted))
    }

    // MARK: 2. Changing class keeps every field (FR-DL-01)

    @Test func changingClassOfADoneDeadlineKeepsItDone() async throws {
        let harness = try makeHarness(at: at(7))
        let planner = harness.planner
        let row = try await save(planner, title: "Portfolio", due: at(7).addingTimeInterval(3 * 86_400))
        await planner.markDone(row.id)
        let done = try #require(planner.row(for: row.id))
        #expect(done.snapshot.status == .done)

        var edit = DeadlineDraft(done)
        edit.dataClass = .college
        #expect(await planner.save(edit))

        let moved = try #require(planner.row(for: row.id))
        #expect(planner.deadlines.count == 1)
        #expect(moved.snapshot.dataClass == .college)
        #expect(moved.snapshot.status == .done)
        #expect(moved.completedAt == done.completedAt)
        #expect(harness.deadlines.pending.withLock { $0.keys.contains { $0.contains(row.id.uuidString) } } == false)

        let repository = DeadlineRepository(stores: harness.model.services.stores)
        let fields = try #require(try await repository.fields(of: row.id, in: .college))
        #expect(fields.createdAt == at(7))
        #expect(fields.originRaw == DeadlineOrigin.manual.rawValue)
        #expect(try await repository.fields(of: row.id, in: .personal) == nil)
    }

    @Test func changingClassKeepsASnoozeWhenTheDueTimeIsUnchanged() async throws {
        let harness = try makeHarness(at: at(7))
        let planner = harness.planner
        let row = try await save(planner, title: "Reading", due: at(7).addingTimeInterval(2 * 86_400))
        let until = at(7).addingTimeInterval(86_400)
        await planner.snooze(row.id, until: until)
        var edit = DeadlineDraft(try #require(planner.row(for: row.id)))
        edit.dataClass = .college
        #expect(await planner.save(edit))
        #expect(planner.row(for: row.id)?.snapshot.snoozedUntil == until)
    }

    // MARK: 3. College deadlines are never donated (BD-04, B-7)

    @Test func collegeDeadlinesAreNotDonatedAndAMoveToCollegeWithdraws() async throws {
        let harness = try makeHarness(at: at(7))
        let planner = harness.planner
        let college = try await save(planner, title: "Thesis", due: at(7).addingTimeInterval(86_400), dataClass: .college)
        #expect(!donor.donated.withLock { $0 }.contains(college.id))

        let personal = try await save(planner, title: "Gym", due: at(7).addingTimeInterval(86_400))
        #expect(donor.donated.withLock { $0 } == [personal.id])

        var edit = DeadlineDraft(personal)
        edit.dataClass = .college
        #expect(await planner.save(edit))
        #expect(donor.withdrawn.withLock { $0 } == [personal.id])
        #expect(donor.donated.withLock { $0 } == [personal.id])
    }

    // MARK: 5. A slot delivered in the app is not re-armed (FR-BRIEF-02)

    @Test func slotDeliveredInAppIsNotRearmedByALaterReschedule() async throws {
        var settings = BriefSettings()
        // 09:45 falls inside the 09:30–10:30 crit, so without the app open it would wait for 10:30.
        settings.slots[0].hour = 9
        settings.slots[0].minute = 45
        let harness = try makeHarness(at: at(9, 50), settings: settings)
        let planner = harness.planner
        await planner.appBecameActive()
        #expect(harness.briefs.scheduled.withLock { Array($0.keys) } == ["brief.morning.2026-10-28"])

        _ = try await save(planner, title: "Essay", due: at(9).addingTimeInterval(3 * 86_400))
        #expect(harness.briefs.scheduled.withLock { Array($0.keys) } == ["brief.morning.2026-10-28"])
    }

    // MARK: 6. Granting permission schedules the brief (FR-BRIEF-05)

    @Test func grantingNotificationPermissionSchedulesTheBrief() async throws {
        let harness = try makeHarness(at: at(7), authorised: false)
        let planner = harness.planner
        await planner.appBecameActive()
        #expect(harness.briefs.scheduled.withLock { $0.isEmpty })
        await planner.requestNotificationAuthorisation()
        #expect(harness.briefs.scheduled.withLock { Array($0.keys) } == ["brief.morning.2026-10-27"])
    }

    // MARK: 7. Done and reschedule update the mirrored reminder (FR-DL-03)

    @Test func rescheduleMovesTheMirroredReminderAndDoneRemovesIt() async throws {
        let store = ReminderStoreSpy(now: at(7), calendar: calendar)
        let harness = try makeHarness(at: at(7), eventStore: store)
        let planner = harness.planner
        await planner.refresh()
        let due = at(7).addingTimeInterval(86_400)
        let row = try await save(planner, title: "Library book", due: due, list: DemoEventStore.remindersID)
        #expect(store.reminders.withLock { $0.values.map(\.due) } == [due])

        await planner.snooze(row.id, until: at(8))
        #expect(store.reminders.withLock { $0.values.map(\.due) } == [due])

        let later = due.addingTimeInterval(9 * 86_400)
        await planner.reschedule(row.id, to: later)
        #expect(store.reminders.withLock { $0.values.map(\.due) } == [later])
        #expect(planner.row(for: row.id)?.mirroredReminderID != nil)

        await planner.markDone(row.id)
        #expect(store.reminders.withLock { $0.isEmpty })
        #expect(planner.row(for: row.id)?.mirroredReminderID == nil)
        #expect(planner.failure == nil)
    }

    // MARK: 8. A failed reminder removal is visible and retried (NFR-REL-01)

    @Test func failedReminderRemovalIsShownAndRetriedOnRefresh() async throws {
        let store = ReminderStoreSpy(now: at(7), calendar: calendar)
        let harness = try makeHarness(at: at(7), eventStore: store)
        let planner = harness.planner
        await planner.refresh()
        // A college deadline mirrored to iCloud only through Mark's override.
        let row = try await save(planner, title: "Crit prep", due: at(7).addingTimeInterval(86_400), dataClass: .college, list: DemoEventStore.remindersID, override: true)
        let reminderID = try #require(row.mirroredReminderID)

        store.failRemovals.withLock { $0 = true }
        var edit = DeadlineDraft(row)
        edit.mirrorOverride = false
        edit.mirrorListID = nil
        #expect(await planner.save(edit))
        #expect(planner.failure == .reminderRemove)
        #expect(planner.pendingReminderRemovals == [reminderID])
        #expect(store.reminders.withLock { $0[reminderID] } != nil)

        planner.failure = nil
        store.failRemovals.withLock { $0 = false }
        await planner.refresh()
        #expect(store.reminders.withLock { $0.isEmpty })
        #expect(planner.pendingReminderRemovals.isEmpty)
        #expect(planner.failure == nil)
    }

    // MARK: 9. Notification actions (FR-OS-05)

    @Test func notificationDoneAndSnoozeActionsChangeTheDeadline() async throws {
        let harness = try makeHarness(at: at(7))
        let planner = harness.planner
        let first = try await save(planner, title: "Form", due: at(7).addingTimeInterval(86_400))
        let second = try await save(planner, title: "Fees", due: at(7).addingTimeInterval(86_400))
        let responder = NotificationResponder(planner: planner, money: harness.model.money)

        await responder.handle(
            category: DeadlineNotificationPlan.categoryIdentifier,
            requestIdentifier: DeadlineNotificationPlan.identifier(deadlineID: first.id, offsetMinutes: 120),
            actionIdentifier: DeadlineNotificationPlan.doneActionIdentifier
        )
        #expect(planner.row(for: first.id)?.snapshot.status == .done)

        await responder.handle(
            category: DeadlineNotificationPlan.categoryIdentifier,
            requestIdentifier: "deadline.\(second.id.uuidString).snooze",
            actionIdentifier: DeadlineNotificationPlan.snoozeActionIdentifier
        )
        #expect(planner.row(for: second.id)?.snapshot.snoozedUntil == at(8))
    }

    // MARK: 12. Unreadable settings are kept

    @Test func unreadableSettingsAreBackedUpBeforeDefaults() throws {
        let defaults = UserDefaults(suiteName: "eagar.fixes.\(UUID().uuidString)")!
        let junk = Data("not json".utf8)
        defaults.set(junk, forKey: BriefSettings.defaultsKey)
        #expect(BriefSettings.load(from: defaults) == BriefSettings())
        #expect(defaults.data(forKey: BriefSettings.backupKey) == junk)
        BriefSettings().save(to: defaults)
        #expect(defaults.data(forKey: BriefSettings.backupKey) == junk)
    }
}
