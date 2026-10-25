import EagarBrief
import EagarCalendar
import EagarCore
import Foundation
import Synchronization
import Testing
@testable import Eagar

/// Records donations instead of sending them to the system.
private final class SpyDonor: IntentDonating {
    let donated = Mutex<[DeadlineSnapshot]>([])
    func donateAddedDeadline(_ snapshot: DeadlineSnapshot) {
        // Mirror SystemIntentDonor's rule so the test checks the planner and the rule together.
        guard snapshot.dataClass != .college else { return }
        donated.withLock { $0.append(snapshot) }
    }
}

/// Records widget snapshots.
private final class SpyWidgets: WidgetPublishing {
    let published = Mutex<[WidgetSnapshot]>([])
    func publish(_ snapshot: WidgetSnapshot) { published.withLock { $0.append(snapshot) } }
}

private struct Clock: EagarClock {
    let date: Date
    func now() -> Date { date }
}

private final class NullDeadlineScheduler: NotificationScheduling {
    func pendingIdentifiers() async -> [String] { [] }
    func add(_ planned: PlannedNotification) async throws {}
    func remove(identifiers: [String]) async {}
    func requestAuthorization() async throws -> Bool { false }
}

@MainActor
struct EgressTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return calendar
    }()
    private var morning: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 7))! }

    private func makeModel(donor: SpyDonor, widgets: SpyWidgets) throws -> AppModel {
        let services = try AppServices.make(
            inMemory: true, secrets: MemorySecrets(), eventStore: DemoEventStore(now: morning, calendar: calendar),
            deadlineNotifications: NullDeadlineScheduler(), donations: donor, widgets: widgets
        )
        let defaults = UserDefaults(suiteName: "eagar.tests.\(UUID().uuidString)")!
        var settings = BriefSettings()
        settings.phrasingMode = .off
        settings.save(to: defaults)
        return AppModel(services: services, defaults: defaults, clock: Clock(date: morning), calendar: calendar)
    }

    /// B-7: adding a college deadline in the app donates nothing to App Intents/Spotlight; a
    /// personal one is donated.
    @Test func Boundary_B7_collegeDeadlinesAreNeverDonated() async throws {
        let donor = SpyDonor()
        let model = try makeModel(donor: donor, widgets: SpyWidgets())
        var college = DeadlineDraft(dueAt: morning.addingTimeInterval(86_400))
        college.title = "Moderation board papers"
        college.dataClass = .college
        #expect(await model.planner.save(college))
        #expect(donor.donated.withLock { $0.isEmpty })

        var personal = DeadlineDraft(dueAt: morning.addingTimeInterval(86_400))
        personal.title = "Renew passport"
        #expect(await model.planner.save(personal))
        #expect(donor.donated.withLock { $0.map(\.title) } == ["Renew passport"])
    }

    /// FR-BRIEF-06: the widget snapshot the app publishes holds no college titles.
    @Test func Boundary_widgetSnapshotHasNoCollegeTitles() async throws {
        let widgets = SpyWidgets()
        let model = try makeModel(donor: SpyDonor(), widgets: widgets)
        await model.planner.refresh()
        let collegeTitles = (model.planner.brief?.allItems ?? []).filter { $0.dataClass == .college }.map(\.title)
        #expect(!collegeTitles.isEmpty) // the demo calendar has college events
        let snapshot = try #require(widgets.published.withLock { $0.last })
        #expect(snapshot.collegeCount == collegeTitles.count)
        for title in collegeTitles {
            #expect(!snapshot.lines.contains { $0.title == title })
        }
    }

    /// FR-CORE-07: the in-app kill switch halts the AI router at once.
    @Test func killSwitchHaltsTheRouter() async throws {
        let model = try makeModel(donor: SpyDonor(), widgets: SpyWidgets())
        await model.setKillSwitch(true)
        #expect(model.killSwitchEngaged)
        #expect(await model.services.router.isHalted)
        await model.setKillSwitch(false)
        #expect(await !model.services.router.isHalted)
    }
}
