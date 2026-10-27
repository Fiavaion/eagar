import EagarCore
import EagarPeople
import EagarStore
import Foundation
import SwiftData

/// A person as the People screen needs it: the snapshot plus Mark's own fields.
struct PersonRecord: Sendable, Hashable, Identifiable {
    let snapshot: PersonSnapshot
    /// Mark's relationship notes. Synced only in CloudKit `encryptedValues` (FR-PEOPLE-02).
    let notes: String
    let contactIdentifier: String?
    var id: UUID { snapshot.id }
}

/// Reads people and contact logs. `PeopleRepository` is the app's reader; tests substitute
/// one that fails, to check that a failed read changes nothing else.
protocol PeopleReading: Sendable {
    func people() async throws(StoreError) -> [PersonRecord]
    func logs() async throws(StoreError) -> [ContactLogSnapshot]
}

/// Reads and changes `Person` and `ContactLog` records in PersonalStore. Keep-in-touch
/// records are personal by construction (BD-26); college-derived interaction dates are never
/// written to them. Not main-actor isolated, so closures run on the store's executor.
struct PeopleRepository: PeopleReading {
    let stores: EagarStores

    func people() async throws(StoreError) -> [PersonRecord] {
        try await stores.personal.fetch(FetchDescriptor<Person>()) {
            PersonRecord(snapshot: $0.snapshot, notes: $0.relationshipNotes, contactIdentifier: $0.contactIdentifier)
        }
    }

    func logs() async throws(StoreError) -> [ContactLogSnapshot] {
        try await stores.personal.fetch(FetchDescriptor<ContactLog>()) { $0.snapshot }.compactMap { $0 }
    }

    /// Adds or updates the person for a picked contact (FR-PEOPLE-01). Returns the person's ID.
    func upsert(_ contact: ContactImport, now: Date) async throws -> UUID {
        try await stores.personal.perform { context in
            try PersonUpsert.upsert(contact, in: context, now: now).personID
        }
    }

    /// Adds a person by name only, without a contact.
    func insert(name: String, now: Date) async throws -> UUID {
        let person = Person(displayName: name, createdAt: now)
        let id = person.personUUID
        try await stores.personal.insert(person)
        return id
    }

    func update(_ id: UUID, _ body: @Sendable (Person) -> Void) async throws {
        try await stores.personal.perform { context in
            try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.personUUID == id })).forEach(body)
        }
    }

    /// Deletes the person and their contact logs.
    func delete(_ id: UUID) async throws {
        try await stores.personal.perform { context in
            try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.personUUID == id })).forEach(context.delete)
            try context.fetch(FetchDescriptor<ContactLog>(predicate: #Predicate { $0.personUUID == id })).forEach(context.delete)
        }
    }

    /// Inserts a manual or nudge contact log and moves the person's last interaction (personal).
    func log(_ draft: ContactLogDraft, now: Date) async throws {
        let personID = draft.personID
        let occurredAt = draft.occurredAt
        try await stores.personal.perform { context in
            context.insert(draft.makeLog(createdAt: now))
            try context.fetch(FetchDescriptor<Person>(predicate: #Predicate { $0.personUUID == personID })).forEach {
                $0.notePersonalInteraction(at: occurredAt)
                $0.snoozedUntil = nil
            }
        }
    }

    /// Writes the personal part of each inference to `lastInteractionAt`. College-derived
    /// dates never reach the record, because it syncs through CloudKit (FR-PEOPLE-03).
    func apply(_ inferences: [UUID: InteractionInference]) async throws {
        let personal = inferences.compactMapValues(\.personalLatest)
        guard !personal.isEmpty else { return }
        try await stores.personal.perform { context in
            for person in try context.fetch(FetchDescriptor<Person>()) {
                if let date = personal[person.personUUID], person.lastInteractionAt.map({ date > $0 }) ?? true {
                    person.notePersonalInteraction(at: date)
                }
            }
        }
    }
}
