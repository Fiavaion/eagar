import EagarCore
import EagarStore
import Foundation
import SwiftData
import Testing
@testable import EagarPeople

struct PersonModelTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func stores() throws -> EagarStores {
        try EagarStores(location: .inMemory, models: [Person.self, ContactLog.self])
    }

    @Test func newPeopleArePersonalWithDefaults() {
        let person = Person(displayName: "Aoife", emailAddresses: [" Aoife@Example.ie ", "aoife@example.ie", "nonsense"], createdAt: now)
        #expect(person.dataClass == .personal)
        #expect(person.cadenceDays == defaultCadenceDays)
        #expect(person.emailAddresses == ["aoife@example.ie"])
        #expect(person.relationshipNotes.isEmpty && !person.workSignalsOptIn)
    }

    @Test func unknownClassReadsAsCollege() {
        let person = Person(displayName: "x", createdAt: now)
        person.dataClassRaw = "mystery"
        #expect(person.dataClass == .college)
    }

    @Test func cadenceAndWeekdaysAreCleaned() {
        let person = Person(displayName: "x", cadenceDays: 0, preferredWeekdays: [9, 5, 5, 1, 0], createdAt: now)
        #expect(person.cadenceDays == minimumCadenceDays)
        #expect(person.preferredWeekdays == [1, 5])
        person.setCadence(days: 10_000)
        #expect(person.cadenceDays == maximumCadenceDays)
    }

    @Test func personalInteractionNeverMovesBackwards() {
        let person = Person(displayName: "x", createdAt: now)
        person.notePersonalInteraction(at: now)
        person.notePersonalInteraction(at: now - 86_400)
        #expect(person.lastInteractionAt == now)
        person.notePersonalInteraction(at: now + 60)
        #expect(person.lastInteractionAt == now + 60)
    }

    @Test func birthdayRoundTripsThroughFields() throws {
        let person = Person(displayName: "x", birthday: Birthday(month: 2, day: 29), createdAt: now)
        #expect(person.birthday == Birthday(month: 2, day: 29))
        #expect(person.birthdayYear == nil)
        person.birthday = nil
        #expect(person.birthdayMonth == nil && person.birthdayDay == nil)
    }

    @Test(arguments: [(2, 30), (4, 31), (13, 1), (0, 5), (6, 0)])
    func invalidBirthdaysAreRejected(month: Int, day: Int) {
        #expect(Birthday(month: month, day: day) == nil)
    }

    @Test func birthdayFromComponentsIgnoresUndefinedYear() {
        var components = DateComponents(month: 3, day: 17)
        components.year = NSDateComponentUndefined
        #expect(Birthday(components: components) == Birthday(month: 3, day: 17))
        #expect(Birthday(components: DateComponents(year: 1990, month: 3, day: 17))?.year == 1990)
        #expect(Birthday(components: DateComponents(day: 17)) == nil)
    }

    @Test func contactLogIsPersonalAndSnapshots() {
        let personID = UUID()
        let log = ContactLog(personUUID: personID, occurredAt: now, note: "Coffee in Rathmines", createdAt: now)
        #expect(log.dataClass == .personal)
        #expect(log.snapshot?.personID == personID)
        #expect(log.snapshot?.kind == .manual)
    }

    // MARK: Upsert (logical uniqueness, FR-PEOPLE-01)

    @Test func upsertInsertsThenUpdatesBySameContactIdentifier() async throws {
        let stores = try stores()
        let first = ContactImport(contactIdentifier: "C1", displayName: "Aoife", emailAddresses: ["aoife@example.ie"], birthday: Birthday(month: 5, day: 4))
        let second = ContactImport(contactIdentifier: "C1", displayName: "Aoife Byrne", emailAddresses: ["ab@example.com"])
        let now = now
        let outcomes = try await stores.personal.perform { context in
            let a = try PersonUpsert.upsert(first, in: context, now: now)
            let b = try PersonUpsert.upsert(second, in: context, now: now)
            return [a, b]
        }
        #expect(outcomes[0] == .inserted(outcomes[0].personID))
        #expect(outcomes[1] == .updated(outcomes[0].personID))
        let people = try await stores.personal.fetch(FetchDescriptor<Person>()) { $0.snapshot }
        #expect(people.count == 1)
        #expect(people[0].displayName == "Aoife Byrne")
        #expect(people[0].emailAddresses == ["aoife@example.ie", "ab@example.com"])
        #expect(people[0].birthday == Birthday(month: 5, day: 4), "an import without a birthday keeps the old one")
    }

    @Test func upsertMatchesByEmailWhenIdentifierDiffers() async throws {
        let stores = try stores()
        let now = now
        try await stores.personal.perform { context in
            try PersonUpsert.upsert(ContactImport(contactIdentifier: "mac-id", displayName: "Ciarán", emailAddresses: ["ciaran@example.ie"]), in: context, now: now)
            try PersonUpsert.upsert(ContactImport(contactIdentifier: "phone-id", displayName: "Ciarán", emailAddresses: ["CIARAN@example.ie"]), in: context, now: now)
        }
        let people = try await stores.personal.fetch(FetchDescriptor<Person>()) { $0.contactIdentifier }
        #expect(people == ["phone-id"])
    }

    @Test func upsertNeverTouchesMarksFields() async throws {
        let stores = try stores()
        let now = now
        try await stores.personal.perform { context in
            let person = Person(contactIdentifier: "C9", displayName: "Niamh", cadenceDays: 14, preferredWeekdays: [5], createdAt: now)
            person.relationshipNotes = "Moved to Galway"
            context.insert(person)
            try PersonUpsert.upsert(ContactImport(contactIdentifier: "C9", displayName: "Niamh K"), in: context, now: now)
        }
        let rows = try await stores.personal.fetch(FetchDescriptor<Person>()) { ($0.cadenceDays, $0.preferredWeekdays, $0.relationshipNotes) }
        #expect(rows.count == 1)
        #expect(rows[0].0 == 14 && rows[0].1 == [5] && rows[0].2 == "Moved to Galway")
    }

    @Test func upsertPicksTheOldestDuplicate() throws {
        let old = Person(contactIdentifier: "C1", displayName: "Old", createdAt: now - 1000)
        let new = Person(contactIdentifier: "C1", displayName: "New", createdAt: now)
        let match = PersonUpsert.match(ContactImport(contactIdentifier: "C1", displayName: "x"), in: [new, old])
        #expect(match === old)
    }

    @Test func noEmailNoIdentifierMatchInserts() {
        let other = Person(contactIdentifier: "C1", displayName: "Other", createdAt: now)
        #expect(PersonUpsert.match(ContactImport(contactIdentifier: "C2", displayName: "Other"), in: [other]) == nil)
    }

    @Test func peopleBelongInPersonalStoreOnly() async throws {
        let stores = try stores()
        await #expect(throws: StoreError.self) {
            try await stores.college.insert(Person(displayName: "Aoife", createdAt: Date()))
        }
    }
}
