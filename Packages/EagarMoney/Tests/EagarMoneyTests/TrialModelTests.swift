import EagarCore
import EagarStore
import Foundation
import SwiftData
import Testing
@testable import EagarMoney

struct TrialModelTests {
    let cal = TestCalendars.dublin
    let now = TestCalendars.date(2026, 10, 26, 12)

    @Test func FR_TRIAL_01_defaults() {
        let trial = Trial(service: "Spotify", price: Decimal(string: "11.99")!, renewsAt: now, createdAt: now)
        #expect(trial.dataClass == .personal)
        #expect(trial.currencyCode == "EUR")
        #expect(trial.safetyMarginDays == 2)
        #expect(trial.reminderDays == [7, 3, 1, 0])
        #expect(trial.status == .active)
        #expect(trial.period == .monthly)
        #expect(trial.isTrial)
    }

    @Test func unknownRawValuesFailSafe() {
        let trial = Trial(service: "x", price: 1, renewsAt: now, createdAt: now)
        trial.dataClassRaw = "mystery"
        trial.statusRaw = "mystery"
        trial.periodRaw = "mystery"
        #expect(trial.dataClass == .college)
        #expect(trial.status == .active)
        #expect(trial.period == .monthly)
    }

    @Test func FR_TRIAL_05_cancelledOnlyOnConfirmation() {
        let trial = Trial(service: "x", price: 1, renewsAt: now, createdAt: now)
        _ = TrialCancelAction.target(for: trial.snapshot)
        #expect(trial.status == .active)
        trial.confirmCancelled(at: now)
        #expect(trial.status == .cancelled)
        #expect(trial.cancelledAt == now)
        trial.reactivate()
        #expect(trial.status == .active && trial.cancelledAt == nil)
    }

    @Test func snapshotRoundTripsThroughUpdate() {
        let trial = Trial(service: "a", price: 1, renewsAt: now, createdAt: now)
        var snapshot = trial.snapshot
        snapshot.service = "Netflix"
        snapshot.price = Decimal(string: "10.99")!
        snapshot.currencyCode = "GBP"
        snapshot.period = .yearly
        snapshot.cancelURL = URL(string: "https://example.com/cancel")
        snapshot.reminderDays = [5]
        trial.update(from: snapshot)
        #expect(trial.snapshot == snapshot)
    }

    @Test func priceSurvivesTheStoreExactly() async throws {
        let stores = try EagarStores(location: .inMemory, models: [Trial.self])
        let id = UUID()
        try await stores.insert(Trial(trialUUID: id, service: "x", price: Decimal(string: "1234.57")!, renewsAt: now, createdAt: now))
        let price = try await stores.personal.perform { context in
            try TrialUpsert.find(id: id, in: context)?.price
        }
        #expect(price == Decimal(string: "1234.57"))
    }

    // MARK: - Upsert

    private func context() throws -> ModelContext {
        let container = try ModelContainer(for: Trial.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return ModelContext(container)
    }

    private func count(_ context: ModelContext) throws -> Int {
        try context.fetchCount(FetchDescriptor<Trial>())
    }

    @Test func upsertUpdatesBySameID() throws {
        let context = try context()
        var snapshot = TrialSnapshot(service: "Netflix", price: 10, renewsAt: now)
        try TrialUpsert.upsert(snapshot, in: context, now: now, calendar: cal)
        snapshot.price = 12
        snapshot.service = "Netflix Standard"
        let stored = try TrialUpsert.upsert(snapshot, in: context, now: now, calendar: cal)
        #expect(try count(context) == 1)
        #expect(stored.price == 12)
    }

    @Test func upsertMatchesSameServiceAndRenewalDay() throws {
        let context = try context()
        let first = try TrialUpsert.upsert(TrialSnapshot(service: "Netflix", price: 10, renewsAt: now), in: context, now: now, calendar: cal)
        let firstID = first.trialUUID
        // A re-imported receipt: new UUID, different case and spacing, later the same day.
        let again = TrialSnapshot(service: "  netflix ", price: 11, renewsAt: now + 3600)
        let stored = try TrialUpsert.upsert(again, in: context, now: now, calendar: cal)
        #expect(try count(context) == 1)
        #expect(stored.trialUUID == firstID)
        #expect(stored.price == 11)
    }

    @Test func upsertKeepsDifferentDaysAndCancelledApart() throws {
        let context = try context()
        let cancelled = try TrialUpsert.upsert(TrialSnapshot(service: "Netflix", price: 10, renewsAt: now), in: context, now: now, calendar: cal)
        cancelled.confirmCancelled(at: now)
        try TrialUpsert.upsert(TrialSnapshot(service: "Netflix", price: 10, renewsAt: now), in: context, now: now, calendar: cal)
        try TrialUpsert.upsert(TrialSnapshot(service: "Netflix", price: 10, renewsAt: now + 86400 * 2), in: context, now: now, calendar: cal)
        try TrialUpsert.upsert(TrialSnapshot(service: "", price: 1, renewsAt: now), in: context, now: now, calendar: cal)
        try TrialUpsert.upsert(TrialSnapshot(service: "", price: 1, renewsAt: now), in: context, now: now, calendar: cal)
        #expect(try count(context) == 5)
    }

    @Test func upsertInsertSetsClassAndCreation() throws {
        let context = try context()
        let stored = try TrialUpsert.upsert(TrialSnapshot(service: "x", price: 1, renewsAt: now, dataClass: .personal), in: context, now: now, calendar: cal)
        #expect(stored.dataClass == .personal)
        #expect(stored.createdAt == now)
    }
}
