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

    /// Every stored field of the deadline with `id` in the store for `dataClass`, as a value.
    func fields(of id: UUID, in dataClass: DataClass) async throws(StoreError) -> DeadlineFields? {
        try await stores.store(for: dataClass).fetch(FetchDescriptor<Deadline>(predicate: #Predicate { $0.deadlineUUID == id })) {
            DeadlineFields($0)
        }.first
    }

    func delete(_ id: UUID, in dataClass: DataClass) async throws {
        try await stores.store(for: dataClass).perform { context in
            try context.fetch(FetchDescriptor<Deadline>(predicate: #Predicate { $0.deadlineUUID == id })).forEach(context.delete)
        }
    }
}

/// Every persisted field of a ``Deadline``, so a record can move between stores without losing
/// status, history or mirror state.
struct DeadlineFields: Sendable, Equatable {
    var deadlineUUID: UUID
    var title: String
    var dueAt: Date
    var isAllDay: Bool
    var originRaw: String
    var reminderOffsetsMinutes: [Int]
    var dataClass: DataClass
    var sourceUUID: UUID?
    var statusRaw: String
    var snoozedUntil: Date?
    var completedAt: Date?
    var createdAt: Date
    var mirroredReminderID: String?
    var mirrorListID: String?
    var mirrorOverride: Bool

    init(_ deadline: Deadline) {
        deadlineUUID = deadline.deadlineUUID
        title = deadline.title
        dueAt = deadline.dueAt
        isAllDay = deadline.isAllDay
        originRaw = deadline.originRaw
        reminderOffsetsMinutes = deadline.reminderOffsetsMinutes
        dataClass = deadline.dataClass
        sourceUUID = deadline.sourceUUID
        statusRaw = deadline.statusRaw
        snoozedUntil = deadline.snoozedUntil
        completedAt = deadline.completedAt
        createdAt = deadline.createdAt
        mirroredReminderID = deadline.mirroredReminderID
        mirrorListID = deadline.mirrorListID
        mirrorOverride = deadline.mirrorOverride
    }

    /// A new model carrying every field.
    func makeDeadline() -> Deadline {
        let deadline = Deadline(
            deadlineUUID: deadlineUUID, title: title, dueAt: dueAt, isAllDay: isAllDay,
            reminderOffsetsMinutes: reminderOffsetsMinutes, dataClass: dataClass, createdAt: createdAt
        )
        deadline.originRaw = originRaw
        deadline.sourceUUID = sourceUUID
        deadline.statusRaw = statusRaw
        deadline.snoozedUntil = snoozedUntil
        deadline.completedAt = completedAt
        deadline.mirroredReminderID = mirroredReminderID
        deadline.mirrorListID = mirrorListID
        deadline.mirrorOverride = mirrorOverride
        return deadline
    }
}
