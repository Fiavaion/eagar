import EagarCore
import EagarSync
import Foundation
import SwiftData

/// Syncs personal deadlines through PersonalStore's CloudKit zone (M1: "PersonalStore records
/// (deadlines, settings) sync between devices"). College deadlines live in CollegeStore and
/// never reach the sync layer.
///
/// Reminder-mirror identifiers are EventKit identifiers local to one device, so they are not
/// synced. Calendar tags (`CalendarRef`) are not synced either: EventKit calendar identifiers
/// differ between devices, so each device keeps its own tags.
public struct DeadlineSyncAdapter: SyncAdapter {
    public let recordType = "Deadline"
    public let fieldNames: Set<String> = [
        "title", "dueAt", "isAllDay", "origin", "offsets", "source", "status", "snoozedUntil",
        "completedAt", "createdAt", "mirrorOverride",
    ]
    public let encryptedFieldNames: Set<String> = []
    public let boolFieldNames: Set<String> = ["isAllDay", "mirrorOverride"]

    public init() {}

    public func recordName(of model: Deadline) -> String { model.deadlineUUID.uuidString }

    public func fields(of model: Deadline) -> SyncFields {
        [
            "title": .string(model.title),
            "dueAt": .date(model.dueAt),
            "isAllDay": .bool(model.isAllDay),
            "origin": .string(model.originRaw),
            "offsets": .ints(model.reminderOffsetsMinutes.map(Int64.init)),
            "source": model.sourceUUID.map { .string($0.uuidString) } ?? .null,
            "status": .string(model.statusRaw),
            "snoozedUntil": model.snoozedUntil.map(SyncValue.date) ?? .null,
            "completedAt": model.completedAt.map(SyncValue.date) ?? .null,
            "createdAt": .date(model.createdAt),
            "mirrorOverride": .bool(model.mirrorOverride),
        ]
    }

    public func all(in context: ModelContext) throws -> [Deadline] {
        try context.fetch(FetchDescriptor<Deadline>())
    }

    public func find(recordName: String, in context: ModelContext) throws -> Deadline? {
        guard let uuid = UUID(uuidString: recordName) else { return nil }
        var descriptor = FetchDescriptor<Deadline>(predicate: #Predicate { $0.deadlineUUID == uuid })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func make(recordName: String, fields: SyncFields, dataClass: DataClass) -> Deadline {
        let deadline = Deadline(
            deadlineUUID: UUID(uuidString: recordName) ?? UUID(), title: "", dueAt: .distantFuture,
            dataClass: dataClass, createdAt: .distantPast
        )
        apply(fields, to: deadline)
        return deadline
    }

    public func apply(_ fields: SyncFields, to model: Deadline) {
        for (name, value) in fields {
            switch (name, value) {
            case let ("title", .string(v)): model.title = v
            case let ("dueAt", .date(v)): model.dueAt = v
            case let ("isAllDay", .bool(v)): model.isAllDay = v
            case let ("origin", .string(v)): model.originRaw = v
            case let ("offsets", .ints(v)): model.reminderOffsetsMinutes = v.map { Int($0) }
            case ("offsets", .null): model.reminderOffsetsMinutes = []
            case let ("source", .string(v)): model.sourceUUID = UUID(uuidString: v)
            case ("source", .null): model.sourceUUID = nil
            case let ("status", .string(v)): model.statusRaw = v
            case let ("snoozedUntil", .date(v)): model.snoozedUntil = v
            case ("snoozedUntil", .null): model.snoozedUntil = nil
            case let ("completedAt", .date(v)): model.completedAt = v
            case ("completedAt", .null): model.completedAt = nil
            case let ("createdAt", .date(v)): model.createdAt = v
            case let ("mirrorOverride", .bool(v)): model.mirrorOverride = v
            default: break
            }
        }
    }
}
