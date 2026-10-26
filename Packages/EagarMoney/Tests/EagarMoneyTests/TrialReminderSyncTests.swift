import EagarCore
import Foundation
import Synchronization
import Testing
@testable import EagarMoney

/// In-memory scheduler recording calls.
final class SpyTrialReminderScheduler: TrialReminderScheduling {
    struct State {
        var pending: [String: PlannedTrialReminder] = [:]
        var foreign: [String] = []
        var removed: [String] = []
        var failAdd = false
    }

    struct AddFailed: Error {}

    let state: Mutex<State>

    init(foreign: [String] = []) {
        var initial = State()
        initial.foreign = foreign
        state = Mutex(initial)
    }

    func pendingIdentifiers() async -> [String] { state.withLock { Array($0.pending.keys) + $0.foreign } }

    func add(_ planned: PlannedTrialReminder) async throws {
        try state.withLock { s in
            if s.failAdd { throw AddFailed() }
            s.pending[planned.id] = planned
        }
    }

    func remove(identifiers: [String]) async {
        state.withLock { s in
            s.removed += identifiers
            identifiers.forEach { s.pending[$0] = nil }
            s.foreign.removeAll { identifiers.contains($0) }
        }
    }
}

struct TrialReminderSyncTests {
    let cal = TestCalendars.dublin
    let now = TestCalendars.date(2026, 10, 1, 12)

    private func trial(_ id: UUID = UUID(), renewal: Date) -> TrialSnapshot {
        TrialSnapshot(id: id, service: "Spotify", price: 11, renewsAt: renewal)
    }

    @Test func FR_TRIAL_02_syncSchedulesEveryPlannedReminder() async {
        let spy = SpyTrialReminderScheduler()
        let item = trial(renewal: TestCalendars.date(2026, 10, 22))
        await TrialReminderSync.sync(trials: [item], now: now, scheduler: spy, calendar: cal)
        let ids = spy.state.withLock { Set($0.pending.keys) }
        #expect(ids == Set([7, 3, 1, 0].map { TrialReminderPlan.identifier(trialID: item.id, daysBefore: $0) }))
        #expect(spy.state.withLock { $0.pending.values.allSatisfy { $0.categoryIdentifier == "trial" } })
    }

    @Test func staleTrialRemindersAreRemovedAndOthersKept() async {
        let stale = TrialReminderPlan.identifier(trialID: UUID(), daysBefore: 3)
        let spy = SpyTrialReminderScheduler(foreign: [stale, "deadline.x.0", "birthday.y.2026"])
        await TrialReminderSync.sync(trials: [], now: now, scheduler: spy, calendar: cal)
        #expect(spy.state.withLock { $0.removed } == [stale])
        #expect(spy.state.withLock { $0.foreign } == ["deadline.x.0", "birthday.y.2026"])
    }

    @Test func cancellingATrialRemovesItsReminders() async {
        let spy = SpyTrialReminderScheduler()
        var item = trial(renewal: TestCalendars.date(2026, 10, 22))
        await TrialReminderSync.sync(trials: [item], now: now, scheduler: spy, calendar: cal)
        item.status = .cancelled
        await TrialReminderSync.sync(trials: [item], now: now, scheduler: spy, calendar: cal)
        #expect(spy.state.withLock { $0.pending.isEmpty })
    }

    @Test func addFailuresDoNotStopTheRest() async {
        let spy = SpyTrialReminderScheduler()
        spy.state.withLock { $0.failAdd = true }
        await TrialReminderSync.sync(trials: [trial(renewal: TestCalendars.date(2026, 10, 22))], now: now, scheduler: spy, calendar: cal)
        #expect(spy.state.withLock { $0.pending.isEmpty })
    }

    @Test func trialIDIsReadFromTheRequestIdentifier() {
        let id = UUID()
        #expect(TrialReminderSync.trialID(fromRequestIdentifier: TrialReminderPlan.identifier(trialID: id, daysBefore: 7)) == id)
        #expect(TrialReminderSync.trialID(fromRequestIdentifier: "deadline.\(id.uuidString).0") == nil)
    }

    @Test func requestCarriesTheCancelTargetButNotTheServiceInUserInfo() throws {
        let item = TrialSnapshot(service: "Spotify", price: 11, renewsAt: TestCalendars.date(2026, 10, 22), cancelURL: URL(string: "https://example.com/cancel"))
        let planned = try #require(TrialReminderPlan.plan([item], now: now, calendar: cal).first)
        let request = UserTrialReminderScheduler.request(for: planned, calendar: cal)
        #expect(request.content.userInfo[UserTrialReminderScheduler.cancelTargetKey] as? String == "https://example.com/cancel")
        #expect(request.content.userInfo[UserTrialReminderScheduler.trialIDKey] as? String == item.id.uuidString)
        #expect(!request.content.userInfo.values.contains { ($0 as? String) == "Spotify" })
    }
}

struct PendingTrialImportStoreTests {
    private func temporaryStore() -> PendingTrialImportStore {
        PendingTrialImportStore(directory: FileManager.default.temporaryDirectory.appending(path: "eagar-pending-\(UUID().uuidString)"))
    }

    @Test func FR_TRIAL_03_roundTripKeepsEveryField() throws {
        let store = temporaryStore()
        let draft = TrialDraft(
            service: "Streamly", price: Decimal(string: "9.99"), currencyCode: "EUR",
            renewsAt: TestCalendars.date(2026, 11, 3), period: .monthly, isTrial: true,
            cancelURL: URL(string: "https://example.com/cancel")
        )
        let item = PendingTrialImport(draft: draft, method: .parser, createdAt: TestCalendars.date(2026, 10, 26, 9))
        try store.save(item)
        #expect(store.all() == [item])
        store.remove(id: item.id)
        #expect(store.all().isEmpty)
    }

    @Test func importsComeBackOldestFirst() throws {
        let store = temporaryStore()
        let later = PendingTrialImport(draft: TrialDraft(service: "B"), method: .parser, createdAt: TestCalendars.date(2026, 10, 26, 10))
        let earlier = PendingTrialImport(draft: TrialDraft(service: "A"), method: .parser, createdAt: TestCalendars.date(2026, 10, 26, 9))
        try store.save(later)
        try store.save(earlier)
        #expect(store.all().map(\.draft.service) == ["A", "B"])
    }

    @Test func corruptFilesAreSkippedAndRemoved() throws {
        let store = temporaryStore()
        let directory = try #require(store.directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let corrupt = directory.appending(path: "\(UUID().uuidString).json")
        try Data("not json".utf8).write(to: corrupt)
        try store.save(PendingTrialImport(draft: TrialDraft(service: "A"), method: .parser, createdAt: .now))
        #expect(store.all().count == 1)
        #expect(!FileManager.default.fileExists(atPath: corrupt.path()))
    }

    @Test func withoutAContainerSavingFailsVisibly() {
        let store = PendingTrialImportStore(directory: nil)
        #expect(!store.isAvailable)
        #expect(throws: PendingTrialImportError.noContainer) {
            try store.save(PendingTrialImport(draft: TrialDraft(), method: .parser, createdAt: .now))
        }
        #expect(store.all().isEmpty)
    }
}
