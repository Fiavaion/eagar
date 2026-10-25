import EagarCalendar
import EagarCore
import EagarStore
import Foundation
import SwiftData

/// Reads and changes `Deadline` records in the store each one's class belongs in. Not
/// main-actor isolated, so its closures run on the stores' own executors.
struct DeadlineRepository: Sendable {
    let stores: EagarStores

    /// Deadlines from both stores, as values.
    func all() async throws(StoreError) -> [DeadlineRow] {
        var rows: [DeadlineRow] = []
        for store in [stores.personal, stores.college] {
            rows += try await store.fetch(FetchDescriptor<Deadline>()) {
                DeadlineRow(snapshot: $0.snapshot, mirrorListID: $0.mirrorListID, mirroredReminderID: $0.mirroredReminderID, completedAt: $0.completedAt)
            }
        }
        return rows
    }

    /// Applies `body` to the deadline with `id` in the store for `dataClass`, then saves.
    func update(_ id: UUID, in dataClass: DataClass, _ body: @Sendable (Deadline) -> Void) async throws {
        try await stores.store(for: dataClass).perform { context in
            try context.fetch(FetchDescriptor<Deadline>(predicate: #Predicate { $0.deadlineUUID == id })).forEach(body)
        }
    }

    func delete(_ id: UUID, in dataClass: DataClass) async throws {
        try await stores.store(for: dataClass).perform { context in
            try context.fetch(FetchDescriptor<Deadline>(predicate: #Predicate { $0.deadlineUUID == id })).forEach(context.delete)
        }
    }
}
