import EagarBrief
import EagarCalendar
import EagarCore
import EagarSuggest
import Foundation
import Synchronization
import Testing
@testable import Eagar

/// Fixed clock (local: the app tests don't link EagarTestSupport, see MemorySecrets).
private struct TestClock: EagarClock {
    let date: Date
    func now() -> Date { date }
}

/// Records deadline notification calls.
private final class SpyDeadlineScheduler: NotificationScheduling {
    struct State {
        var pending: [String: PlannedNotification] = [:]
        var authorisationRequests = 0
    }
    let state = Mutex(State())
    func pendingIdentifiers() async -> [String] { state.withLock { Array($0.pending.keys) } }
    func add(_ planned: PlannedNotification) async throws { state.withLock { $0.pending[planned.id] = planned } }
    func remove(identifiers: [String]) async { state.withLock { s in identifiers.forEach { s.pending[$0] = nil } } }
    func requestAuthorization() async throws -> Bool { state.withLock { $0.authorisationRequests += 1 }; return true }
}

/// Records brief notification calls.
private final class SpyBriefScheduler: BriefNotificationScheduling {
    let scheduled = Mutex<[String: (content: BriefNotificationContent, date: Date)]>([:])
    func pendingBriefIdentifiers() async -> [String] { scheduled.withLock { Array($0.keys) } }
    func schedule(_ content: BriefNotificationContent, at date: Date, identifier: String) async throws {
        scheduled.withLock { $0[identifier] = (content, date) }
    }
    func remove(identifiers: [String]) async { scheduled.withLock { s in identifiers.forEach { s[$0] = nil } } }
}

@MainActor
struct PlannerModelTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return calendar
    }()
    private let deadlines = SpyDeadlineScheduler()
    private let briefs = SpyBriefScheduler()

    /// 07:00 on a fixed day, before the 08:00 morning slot.
    private var morning: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 7))!
    }

    private func makePlanner(at now: Date) throws -> PlannerModel { try makeModel(at: now).planner }

    private func makeModel(at now: Date) throws -> AppModel {
        let services = try AppServices.make(
            inMemory: true, secrets: MemorySecrets(), eventStore: DemoEventStore(now: now, calendar: calendar),
            deadlineNotifications: deadlines, briefNotifications: briefs
        )
        let defaults = UserDefaults(suiteName: "eagar.tests.\(UUID().uuidString)")!
        var settings = BriefSettings()
        settings.phrasingMode = .off
        settings.save(to: defaults)
        return AppModel(services: services, defaults: defaults, clock: TestClock(date: now), calendar: calendar)
    }

    @Test func briefComposesFromTheFakeCalendar() async throws {
        let planner = try makePlanner(at: morning)
        await planner.refresh()
        let brief = try #require(planner.brief)
        let titles = brief.allItems.map(\.title)
        #expect(titles.contains("Studio crit"))
        #expect(titles.contains("Lunch with Sam"))
        #expect(brief.sections.first?.kind == .today)
        #expect(planner.timeline.count == 6)
    }

    @Test func collegeCalendarEventsAreClassifiedCollege() async throws {
        let planner = try makePlanner(at: morning)
        await planner.refresh()
        let ncad = try #require(planner.eventCalendars.first { $0.id == DemoEventStore.collegeID })
        #expect(planner.tag(for: ncad).dataClass == .college)
        #expect(planner.tag(for: ncad).confirmed == false)
        let items = try #require(planner.brief?.allItems)
        #expect(items.first { $0.title == "Studio crit" }?.dataClass == .college)
        #expect(items.first { $0.title == "Lunch with Sam" }?.dataClass == .personal)
        #expect(planner.isCollegeCalendarMissing == false)
    }

    @Test func retaggingACalendarReclassifiesItsEvents() async throws {
        let planner = try makePlanner(at: morning)
        await planner.refresh()
        let home = try #require(planner.eventCalendars.first { $0.id == DemoEventStore.homeID })
        await planner.setTag(home, dataClass: .college, includeInBrief: true)
        #expect(planner.tag(for: home).confirmed)
        #expect(planner.brief?.allItems.first { $0.title == "Lunch with Sam" }?.dataClass == .college)
    }

    @Test func excludedCalendarLeavesTheBrief() async throws {
        let planner = try makePlanner(at: morning)
        await planner.refresh()
        let home = try #require(planner.eventCalendars.first { $0.id == DemoEventStore.homeID })
        await planner.setTag(home, dataClass: .personal, includeInBrief: false)
        #expect(planner.brief?.allItems.contains { $0.title == "Lunch with Sam" } == false)
    }

    @Test func savingADeadlineSchedulesItsNotifications() async throws {
        let planner = try makePlanner(at: morning)
        await planner.refresh()
        var draft = planner.newDeadlineDraft()
        draft.title = "Essay"
        draft.dueAt = morning.addingTimeInterval(3 * 86_400)
        #expect(await planner.save(draft))
        let saved = try #require(planner.deadlines.first)
        let pending = deadlines.state.withLock { $0.pending }
        #expect(Set(pending.keys) == [
            DeadlineNotificationPlan.identifier(deadlineID: saved.id, offsetMinutes: 1440),
            DeadlineNotificationPlan.identifier(deadlineID: saved.id, offsetMinutes: 120),
        ])
        #expect(deadlines.state.withLock { $0.authorisationRequests } == 1)

        // A second save does not ask again; marking done removes its notifications.
        draft.title = "Second essay"
        #expect(await planner.save(draft))
        #expect(deadlines.state.withLock { $0.authorisationRequests } == 1)
        await planner.markDone(saved.id)
        #expect(deadlines.state.withLock { $0.pending.keys.contains { $0.contains(saved.id.uuidString) } } == false)
    }

    @Test func collegeDeadlineNotificationsHaveNoTitle() async throws {
        let planner = try makePlanner(at: morning)
        var draft = planner.newDeadlineDraft()
        draft.title = "Thesis draft"
        draft.dataClass = .college
        draft.dueAt = morning.addingTimeInterval(2 * 86_400)
        #expect(await planner.save(draft))
        let pending = deadlines.state.withLock { Array($0.pending.values) }
        #expect(!pending.isEmpty)
        #expect(pending.allSatisfy { !$0.title.contains("Thesis") && !$0.body.contains("Thesis") })
        #expect(planner.deadlines.first?.snapshot.dataClass == .college)
    }

    @Test func changingADeadlineClassMovesIt() async throws {
        let planner = try makePlanner(at: morning)
        var draft = planner.newDeadlineDraft()
        draft.title = "Portfolio"
        #expect(await planner.save(draft))
        var edit = DeadlineDraft(try #require(planner.deadlines.first))
        edit.dataClass = .college
        #expect(await planner.save(edit))
        #expect(planner.deadlines.count == 1)
        #expect(planner.deadlines.first?.snapshot.dataClass == .college)
        #expect(planner.deadlines.first?.id == edit.id)
    }

    @Test func overdueDeadlineLeadsTheBriefAndSnoozeHidesIt() async throws {
        let planner = try makePlanner(at: morning)
        var draft = planner.newDeadlineDraft()
        draft.title = "Library book"
        draft.dueAt = morning.addingTimeInterval(-3600)
        #expect(await planner.save(draft))
        await planner.refresh()
        let first = try #require(planner.brief?.sections.first)
        #expect(first.kind == .overdue)
        let item = try #require(first.items.first)
        await planner.snooze(item, until: planner.snoozeInAnHour)
        #expect(planner.brief?.sections.contains { $0.kind == .overdue } == false)
    }

    @Test func briefNotificationIsScheduledAtTheFirstBreakpointWithCountsOnly() async throws {
        let planner = try makePlanner(at: morning)
        await planner.appBecameActive()
        let id = BriefNotificationID.make(slot: .morning, day: morning, calendar: calendar)
        #expect(id == "brief.morning.2026-10-27")
        let scheduled = try #require(briefs.scheduled.withLock { $0[id] })
        // Nothing ends between 08:00 and 08:45 in the fake day, so the brief waits the full 45 minutes.
        #expect(scheduled.date == calendar.date(bySettingHour: 8, minute: 45, second: 0, of: morning))
        #expect(scheduled.content.threadIdentifier == "brief")
        for title in ["Studio crit", "Submission week", "Printmaking", "Lunch"] {
            #expect(!scheduled.content.body.contains(title))
            #expect(!scheduled.content.title.contains(title))
        }
    }

    @Test func passedSlotIsScheduledForTomorrow() async throws {
        let evening = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: morning)!
        let planner = try makePlanner(at: evening)
        await planner.appBecameActive()
        let ids = briefs.scheduled.withLock { Array($0.keys) }
        #expect(ids == ["brief.morning.2026-10-28"])
    }

    @Test func briefActionsAreLogged() async throws {
        let model = try makeModel(at: morning)
        let planner = model.planner
        await planner.refresh()
        await planner.briefOpened()
        let item = try #require(planner.brief?.allItems.first)
        await planner.rate(item, helpful: true)
        await planner.perform(.dismiss, on: item)
        #expect(planner.itemStates[item.id] == .dismiss)
        #expect(planner.ratings[item.id] == true)
        let kinds = try await model.services.eventLog.records().map(\.kind)
        #expect(kinds.contains(.briefOpened))
        #expect(kinds.contains(.thumbsUp))
        #expect(kinds.contains(.itemDismissed))
    }
}
