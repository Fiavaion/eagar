import EagarCalendar
import EagarCore
import EagarMoney
import Foundation
import Synchronization
import Testing
@testable import Eagar

private struct FixedClock: EagarClock {
    let date: Date
    func now() -> Date { date }
}

/// Records trial reminder calls.
final class SpyTrialReminders: TrialReminderScheduling {
    let pending = Mutex<[String: PlannedTrialReminder]>([:])
    func pendingIdentifiers() async -> [String] { pending.withLock { Array($0.keys) } }
    func add(_ planned: PlannedTrialReminder) async throws { pending.withLock { $0[planned.id] = planned } }
    func remove(identifiers: [String]) async { pending.withLock { p in identifiers.forEach { p[$0] = nil } } }
}

/// Records deadline notification calls.
final class SpyDeadlineNotifications: NotificationScheduling {
    let pending = Mutex<[String: PlannedNotification]>([:])
    func pendingIdentifiers() async -> [String] { pending.withLock { Array($0.keys) } }
    func add(_ planned: PlannedNotification) async throws { pending.withLock { $0[planned.id] = planned } }
    func remove(identifiers: [String]) async { pending.withLock { p in identifiers.forEach { p[$0] = nil } } }
    func requestAuthorization() async throws -> Bool { true }
}

@MainActor
struct MoneyModelTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return calendar
    }()
    private var morning: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 7))! }
    private let trialReminders = SpyTrialReminders()
    private let deadlineNotifications = SpyDeadlineNotifications()

    private func makeModel(pending: PendingTrialImportStore = PendingTrialImportStore(directory: nil)) throws -> AppModel {
        let services = try AppServices.make(
            inMemory: true, secrets: MemorySecrets(), eventStore: DemoEventStore(now: morning, calendar: calendar),
            deadlineNotifications: deadlineNotifications, trialReminders: trialReminders, pendingImports: pending
        )
        let defaults = UserDefaults(suiteName: "eagar.tests.\(UUID().uuidString)")!
        return AppModel(services: services, defaults: defaults, clock: FixedClock(date: morning), calendar: calendar)
    }

    private func draft(_ model: AppModel, service: String = "Streamly", renewalInDays: Int = 9) -> TrialEditorDraft {
        var draft = model.money.newDraft()
        draft.service = service
        draft.price = Decimal(string: "9.99")!
        draft.renewsAt = calendar.date(byAdding: .day, value: renewalInDays, to: calendar.startOfDay(for: morning))!
        return draft
    }

    /// FR-TRIAL-01/02, FR-DL-01: saving a trial schedules its 7/3/1/0-day reminders and shows
    /// its cancel-by day among the deadlines, without any deadline notification for it.
    @Test func FR_TRIAL_02_saveSchedulesRemindersAndShowsCancelByWithoutDoubleNotifying() async throws {
        let model = try makeModel()
        await model.appBecameActive()
        #expect(await model.money.save(draft(model)))
        let trial = try #require(model.money.trials.first)

        let reminders = trialReminders.pending.withLock { $0 }
        #expect(Set(reminders.values.map(\.daysBefore)) == [7, 3, 1, 0])
        #expect(reminders.values.allSatisfy { $0.trialID == trial.id })

        // Cancel-by = renewal (day 9) minus 2 days.
        let row = try #require(model.planner.upcomingDeadlines.first { $0.id == trial.id })
        #expect(row.snapshot.origin == .trial)
        #expect(row.snapshot.dueAt == calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: morning)))

        // The trial deadline is shown, never stored or notified as a deadline.
        #expect(model.planner.deadlines.isEmpty)
        #expect(deadlineNotifications.pending.withLock { $0.keys.allSatisfy { !$0.contains(trial.id.uuidString) } })
    }

    @Test func FR_TRIAL_05_onlyConfirmationRecordsCancellation() async throws {
        let model = try makeModel()
        #expect(await model.money.save(draft(model)))
        let id = try #require(model.money.trials.first?.id)
        #expect(model.money.cancelTarget(id) == TrialCancelAction.appStoreSubscriptionsURL)
        #expect(model.money.trial(id)?.status == .active) // opening the page changes nothing
        await model.money.confirmCancelled(id)
        #expect(model.money.trial(id)?.status == .cancelled)
        #expect(trialReminders.pending.withLock { $0.isEmpty })
        #expect(model.planner.upcomingDeadlines.allSatisfy { $0.id != id })
    }

    @Test func trialsAboutToBillReachTheBrief() async throws {
        let model = try makeModel()
        await model.appBecameActive()
        #expect(await model.money.save(draft(model, renewalInDays: 4)))
        let trials = try #require(model.planner.brief?.sections.first { $0.kind == .trials })
        #expect(trials.items.map(\.title) == ["Streamly"])
    }

    @Test func savingTheSameImportTwiceKeepsOneTrial() async throws {
        let model = try makeModel()
        #expect(await model.money.save(draft(model)))
        #expect(await model.money.save(draft(model)))
        #expect(model.money.trials.count == 1)
    }

    /// FR-TRIAL-03: what the share extension writes comes back as a proposal; confirming
    /// stores it and removes the hand-over file; nothing is stored before.
    @Test func FR_TRIAL_03_shareExtensionPendingImportRoundTrip() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "eagar-app-pending-\(UUID().uuidString)")
        let store = PendingTrialImportStore(directory: directory)
        let shared = PendingTrialImport(
            draft: TrialDraft(service: "Lingo Plus", price: Decimal(string: "6.49"), currencyCode: "EUR", renewsAt: calendar.date(byAdding: .day, value: 10, to: morning)),
            method: .parser, createdAt: morning
        )
        try store.save(shared)

        let model = try makeModel(pending: store)
        await model.appBecameActive()
        let review = try #require(model.money.review)
        #expect(review.service == "Lingo Plus")
        #expect(review.isProposed)
        #expect(model.money.trials.isEmpty)

        #expect(await model.money.save(review))
        #expect(model.money.trials.map(\.service) == ["Lingo Plus"])
        #expect(store.all().isEmpty)
    }

    @Test func discardingAPendingImportStoresNothing() async throws {
        let store = PendingTrialImportStore(directory: FileManager.default.temporaryDirectory.appending(path: "eagar-app-pending-\(UUID().uuidString)"))
        try store.save(PendingTrialImport(draft: TrialDraft(service: "X"), method: .parser, createdAt: morning))
        let model = try makeModel(pending: store)
        await model.money.refresh()
        let review = try #require(model.money.review)
        model.money.discardReview(review)
        #expect(model.money.review == nil)
        #expect(store.all().isEmpty)
        #expect(model.money.trials.isEmpty)
    }

    @Test func importedCancelURLsMustBeWebLinks() {
        var draft = TrialEditorDraft(startedAt: morning, renewsAt: morning)
        draft.cancelURLString = "example.com/cancel"
        #expect(draft.cancelURL?.absoluteString == "https://example.com/cancel")
        draft.cancelURLString = "javascript:alert(1)"
        #expect(draft.cancelURL == nil)
    }
}
