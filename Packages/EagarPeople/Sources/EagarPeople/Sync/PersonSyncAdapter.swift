import EagarCore
import EagarSync
import Foundation
import SwiftData

/// Syncs keep-in-touch people through PersonalStore's CloudKit zone (FR-PEOPLE-02, BD-02).
///
/// Relationship notes and everything that identifies the person (name, contact identifier,
/// email addresses, birthday) travel only in CloudKit `encryptedValues`. Scheduling fields
/// (cadence, weekdays, snooze, opt-in) are plain.
///
/// `lastInteractionAt` is personal-derived by construction: college-derived interaction dates
/// are never written to ``Person`` (see ``InteractionInference``), so nothing college-tainted
/// reaches this adapter.
public struct PersonSyncAdapter: SyncAdapter {
    public let recordType = "Person"
    public let fieldKinds: [String: SyncFieldKind] = [
        "displayName": .string, "contactIdentifier": .string, "emailAddresses": .strings,
        "birthdayMonth": .int, "birthdayDay": .int, "birthdayYear": .int,
        "cadenceDays": .int, "preferredWeekdays": .ints, "relationshipNotes": .string,
        "lastInteractionAt": .date, "snoozedUntil": .date, "workSignalsOptIn": .bool, "createdAt": .date,
    ]
    public let encryptedFieldNames: Set<String> = [
        "displayName", "contactIdentifier", "emailAddresses", "birthdayMonth", "birthdayDay", "birthdayYear", "relationshipNotes",
    ]

    public init() {}

    public func recordName(of model: Person) -> String { model.personUUID.uuidString }

    public func fields(of model: Person) -> SyncFields {
        [
            "displayName": .string(model.displayName),
            "contactIdentifier": model.contactIdentifier.map(SyncValue.string) ?? .null,
            "emailAddresses": .strings(model.emailAddresses),
            "birthdayMonth": model.birthdayMonth.map { .int(Int64($0)) } ?? .null,
            "birthdayDay": model.birthdayDay.map { .int(Int64($0)) } ?? .null,
            "birthdayYear": model.birthdayYear.map { .int(Int64($0)) } ?? .null,
            "cadenceDays": .int(Int64(model.cadenceDays)),
            "preferredWeekdays": .ints(model.preferredWeekdays.map(Int64.init)),
            "relationshipNotes": .string(model.relationshipNotes),
            "lastInteractionAt": model.lastInteractionAt.map(SyncValue.date) ?? .null,
            "snoozedUntil": model.snoozedUntil.map(SyncValue.date) ?? .null,
            "workSignalsOptIn": .bool(model.workSignalsOptIn),
            "createdAt": .date(model.createdAt),
        ]
    }

    public func all(in context: ModelContext) throws -> [Person] {
        try context.fetch(FetchDescriptor<Person>())
    }

    public func find(recordName: String, in context: ModelContext) throws -> Person? {
        guard let uuid = UUID(uuidString: recordName) else { return nil }
        return try PersonUpsert.find(uuid, in: context)
    }

    public func make(recordName: String, fields: SyncFields, dataClass: DataClass) -> Person {
        let person = Person(personUUID: UUID(uuidString: recordName) ?? UUID(), displayName: "", dataClass: dataClass, createdAt: .distantPast)
        apply(fields, to: person)
        return person
    }

    public func apply(_ fields: SyncFields, to model: Person) {
        for (name, value) in fields {
            switch (name, value) {
            case let ("displayName", .string(v)): model.displayName = v
            case let ("contactIdentifier", .string(v)): model.contactIdentifier = v
            case ("contactIdentifier", .null): model.contactIdentifier = nil
            case let ("emailAddresses", .strings(v)): model.setEmailAddresses(v)
            case let ("birthdayMonth", .int(v)): model.birthdayMonth = Int(v)
            case ("birthdayMonth", .null): model.birthdayMonth = nil
            case let ("birthdayDay", .int(v)): model.birthdayDay = Int(v)
            case ("birthdayDay", .null): model.birthdayDay = nil
            case let ("birthdayYear", .int(v)): model.birthdayYear = Int(v)
            case ("birthdayYear", .null): model.birthdayYear = nil
            case let ("cadenceDays", .int(v)): model.setCadence(days: Int(clamping: v))
            case let ("preferredWeekdays", .ints(v)): model.setPreferredWeekdays(v.map { Int(clamping: $0) })
            case let ("relationshipNotes", .string(v)): model.relationshipNotes = v
            case let ("lastInteractionAt", .date(v)): model.lastInteractionAt = v
            case ("lastInteractionAt", .null): model.lastInteractionAt = nil
            case let ("snoozedUntil", .date(v)): model.snoozedUntil = v
            case ("snoozedUntil", .null): model.snoozedUntil = nil
            case let ("workSignalsOptIn", .bool(v)): model.workSignalsOptIn = v
            case let ("createdAt", .date(v)): model.createdAt = v
            default: break
            }
        }
    }
}

/// Syncs manual contact logs (FR-PEOPLE-03). The free-text note travels only in `encryptedValues`.
public struct ContactLogSyncAdapter: SyncAdapter {
    public let recordType = "ContactLog"
    public let fieldKinds: [String: SyncFieldKind] = [
        "person": .string, "occurredAt": .date, "kind": .string, "note": .string, "createdAt": .date,
    ]
    public let encryptedFieldNames: Set<String> = ["note"]

    public init() {}

    public func recordName(of model: ContactLog) -> String { model.logUUID.uuidString }

    public func fields(of model: ContactLog) -> SyncFields {
        [
            "person": model.personUUID.map { .string($0.uuidString) } ?? .null,
            "occurredAt": .date(model.occurredAt),
            "kind": .string(model.kindRaw),
            "note": .string(model.note),
            "createdAt": .date(model.createdAt),
        ]
    }

    public func all(in context: ModelContext) throws -> [ContactLog] {
        try context.fetch(FetchDescriptor<ContactLog>())
    }

    public func find(recordName: String, in context: ModelContext) throws -> ContactLog? {
        guard let uuid = UUID(uuidString: recordName) else { return nil }
        var descriptor = FetchDescriptor<ContactLog>(predicate: #Predicate { $0.logUUID == uuid })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    public func make(recordName: String, fields: SyncFields, dataClass: DataClass) -> ContactLog {
        let log = ContactLog(logUUID: UUID(uuidString: recordName) ?? UUID(), personUUID: UUID(), occurredAt: .distantPast, dataClass: dataClass, createdAt: .distantPast)
        log.personUUID = nil
        apply(fields, to: log)
        return log
    }

    public func apply(_ fields: SyncFields, to model: ContactLog) {
        for (name, value) in fields {
            switch (name, value) {
            case let ("person", .string(v)): model.personUUID = UUID(uuidString: v)
            case ("person", .null): model.personUUID = nil
            case let ("occurredAt", .date(v)): model.occurredAt = v
            case let ("kind", .string(v)): model.kindRaw = v
            case let ("note", .string(v)): model.note = v
            case let ("createdAt", .date(v)): model.createdAt = v
            default: break
            }
        }
    }
}
