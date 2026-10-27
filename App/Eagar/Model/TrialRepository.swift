import EagarCore
import EagarMoney
import EagarStore
import Foundation
import SwiftData

/// Reads every trial. `TrialRepository` is the app's reader; tests substitute one that fails,
/// to check that a failed read changes nothing else.
protocol TrialReading: Sendable {
    func all() async throws(StoreError) -> [TrialSnapshot]
}

/// Reads and changes `Trial` records in PersonalStore. Trials are personal (Mark enters or
/// imports them himself), so CollegeStore never holds one. Not main-actor isolated, so its
/// closures run on the store's own executor.
struct TrialRepository: TrialReading {
    let stores: EagarStores

    func all() async throws(StoreError) -> [TrialSnapshot] {
        try await stores.personal.fetch(FetchDescriptor<Trial>()) { $0.snapshot }
    }

    /// Adds or updates through `TrialUpsert` (logical uniqueness), then saves with the class check.
    func upsert(_ snapshot: TrialSnapshot, now: Date, calendar: Calendar) async throws {
        try await stores.personal.perform { context in
            _ = try TrialUpsert.upsert(snapshot, in: context, now: now, calendar: calendar)
        }
    }

    func update(_ id: UUID, _ body: @Sendable (Trial) -> Void) async throws {
        try await stores.personal.perform { context in
            try context.fetch(FetchDescriptor<Trial>(predicate: #Predicate { $0.trialUUID == id })).forEach(body)
        }
    }

    func delete(_ id: UUID) async throws {
        try await stores.personal.perform { context in
            try context.fetch(FetchDescriptor<Trial>(predicate: #Predicate { $0.trialUUID == id })).forEach(context.delete)
        }
    }
}
