import EagarCore
import Foundation
import SwiftData

/// Logical uniqueness for ``Person`` (the schema has no unique constraints, for CloudKit).
///
/// Run inside `ClassifiedStore.perform` on PersonalStore, which saves with the class check.
public enum PersonUpsert {
    /// The outcome of an import.
    public enum Outcome: Sendable, Hashable {
        case inserted(UUID)
        case updated(UUID)

        public var personID: UUID {
            switch self {
            case let .inserted(id), let .updated(id): id
            }
        }
    }

    /// Adds or updates the person for `contact` (FR-PEOPLE-01).
    ///
    /// Matching order: same contact identifier, then any shared email address (contact
    /// identifiers can differ between devices, so a synced person may carry another device's
    /// identifier). When several people match, the oldest wins. An update refreshes name, email
    /// addresses (merged) and birthday (only when the import has one); cadence, weekday
    /// preferences and relationship notes are Mark's and are never touched.
    @discardableResult
    public static func upsert(_ contact: ContactImport, in context: ModelContext, now: Date) throws -> Outcome {
        let people = try context.fetch(FetchDescriptor<Person>())
        if let existing = match(contact, in: people) {
            existing.contactIdentifier = contact.contactIdentifier
            existing.displayName = contact.displayName
            existing.setEmailAddresses(existing.emailAddresses + contact.emailAddresses)
            if let birthday = contact.birthday { existing.birthday = birthday }
            return .updated(existing.personUUID)
        }
        let person = Person(
            contactIdentifier: contact.contactIdentifier, displayName: contact.displayName,
            emailAddresses: contact.emailAddresses, birthday: contact.birthday, createdAt: now
        )
        context.insert(person)
        return .inserted(person.personUUID)
    }

    /// The existing person `contact` refers to, if any.
    static func match(_ contact: ContactImport, in people: [Person]) -> Person? {
        let oldestFirst = people.sorted { ($0.createdAt, $0.personUUID.uuidString) < ($1.createdAt, $1.personUUID.uuidString) }
        if let byID = oldestFirst.first(where: { $0.contactIdentifier == contact.contactIdentifier }) { return byID }
        let emails = Set(normalisedEmails(contact.emailAddresses))
        guard !emails.isEmpty else { return nil }
        return oldestFirst.first { !emails.isDisjoint(with: $0.emailAddresses) }
    }

    /// Finds a person by UUID.
    public static func find(_ id: UUID, in context: ModelContext) throws -> Person? {
        var descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.personUUID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }
}
