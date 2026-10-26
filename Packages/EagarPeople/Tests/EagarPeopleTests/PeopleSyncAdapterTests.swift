import CloudKit
import EagarCore
import EagarStore
import EagarSync
import Foundation
import SwiftData
import Testing
@testable import EagarPeople

struct PeopleSyncAdapterTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let notes = "Synthetic note: met at the Dún Laoghaire pier walk, prefers Thursdays"

    private func samplePerson() -> Person {
        let person = Person(
            contactIdentifier: "C-123", displayName: "Aoife Ní Bhriain", emailAddresses: ["aoife@example.ie"],
            birthday: Birthday(month: 2, day: 29, year: 1996), cadenceDays: 21, preferredWeekdays: [5, 7], createdAt: now - 1000
        )
        person.relationshipNotes = notes
        person.lastInteractionAt = now - 86_400
        person.snoozedUntil = now + 86_400
        person.workSignalsOptIn = true
        return person
    }

    private func record<A: SyncAdapter>(for model: A.Model, adapter: A) throws -> CKRecord {
        let record = CKRecord(recordType: adapter.recordType, recordID: CKRecord.ID(recordName: adapter.recordName(of: model), zoneID: SyncZone.id))
        try RecordCodec.write(adapter.fields(of: model), dataClass: model.dataClass, encrypted: adapter.encryptedFieldNames, into: record)
        return record
    }

    /// PRD §10 M2: "Relationship notes stored with encryptedValues (record inspection test)".
    @Test func relationshipNotesAreStoredInEncryptedValuesOnly() throws {
        let adapter = PersonSyncAdapter()
        let record = try record(for: samplePerson(), adapter: adapter)
        #expect(record.encryptedValues["relationshipNotes"] as? String == notes)
        #expect(record["relationshipNotes"] == nil)
        // `allKeys()` lists encrypted keys too, but subscripting reads plain values only:
        // no plain value carries the note text, under any key.
        for key in record.allKeys() {
            #expect((record[key] as? String) != notes, "plain field \(key) carries the note")
        }
    }

    @Test func identifyingFieldsAreEncrypted() throws {
        let adapter = PersonSyncAdapter()
        let record = try record(for: samplePerson(), adapter: adapter)
        for key in ["displayName", "contactIdentifier", "emailAddresses", "birthdayMonth", "birthdayDay", "birthdayYear"] {
            #expect(record[key] == nil, "\(key) must not be a plain value")
            #expect(record.encryptedValues[key] != nil, "\(key) must be in encryptedValues")
        }
        #expect(record["cadenceDays"] as? Int64 == 21)
    }

    @Test func personRoundTripsThroughACloudKitRecord() throws {
        let adapter = PersonSyncAdapter()
        let person = samplePerson()
        let fields = adapter.fields(of: person)
        #expect(Set(fields.keys) == adapter.fieldNames)
        #expect(adapter.encryptedFieldNames.isSubset(of: adapter.fieldNames))
        let read = try RecordCodec.read(try record(for: person, adapter: adapter), kinds: adapter.fieldKinds, encrypted: adapter.encryptedFieldNames)
        #expect(read.fields == fields)
        let copy = adapter.make(recordName: adapter.recordName(of: person), fields: read.fields, dataClass: read.dataClass)
        #expect(adapter.fields(of: copy) == fields)
        #expect(copy.personUUID == person.personUUID)
        #expect(copy.dataClass == .personal)
        #expect(copy.birthday == Birthday(month: 2, day: 29, year: 1996))
    }

    @Test func nullsClearOptionalPersonFields() {
        let adapter = PersonSyncAdapter()
        let person = samplePerson()
        adapter.apply(["contactIdentifier": .null, "birthdayMonth": .null, "birthdayDay": .null, "birthdayYear": .null, "lastInteractionAt": .null, "snoozedUntil": .null], to: person)
        #expect(person.contactIdentifier == nil && person.birthday == nil && person.lastInteractionAt == nil && person.snoozedUntil == nil)
    }

    @Test func contactLogNoteIsEncryptedAndRoundTrips() throws {
        let adapter = ContactLogSyncAdapter()
        let log = ContactLog(personUUID: UUID(), occurredAt: now, kind: .nudge, note: notes, createdAt: now)
        let record = try record(for: log, adapter: adapter)
        #expect(record.encryptedValues["note"] as? String == notes)
        #expect(record["note"] == nil)
        let read = try RecordCodec.read(record, kinds: adapter.fieldKinds, encrypted: adapter.encryptedFieldNames)
        let copy = adapter.make(recordName: adapter.recordName(of: log), fields: read.fields, dataClass: read.dataClass)
        #expect(adapter.fields(of: copy) == adapter.fields(of: log))
        #expect(copy.kind == .nudge && copy.personUUID == log.personUUID)
    }

    /// A Person reading as college (for example an unknown stored class) is refused by the codec.
    @Test func Boundary_collegeClassPersonIsRefusedBySync() {
        let person = samplePerson()
        person.dataClassRaw = "unknown"
        #expect(throws: SyncError.collegeRecordRefused) {
            _ = try record(for: person, adapter: PersonSyncAdapter())
        }
    }

    /// FR-PEOPLE-03 with the work opt-in on: the college-derived interaction date is used on the
    /// device but never appears in the CloudKit record, plain or encrypted.
    @Test func Boundary_collegeDerivedInteractionNeverReachesCloudKit() throws {
        let person = Person(displayName: "Aoife", emailAddresses: ["aoife@example.ie"], createdAt: now - 100 * 86_400)
        person.workSignalsOptIn = true
        let collegeDate = now - 86_400
        let personalDate = now - 20 * 86_400
        let inference = InteractionInferrer.infer(person: person.snapshot, signals: [
            InteractionSignal(date: collegeDate, kind: .mail, dataClass: .college),
            InteractionSignal(date: personalDate, kind: .manualLog, dataClass: .personal),
        ])
        #expect(inference.effectiveLatest == collegeDate && inference.effectiveClass == .college)
        person.apply(inference)
        let record = try record(for: person, adapter: PersonSyncAdapter())
        #expect(record["lastInteractionAt"] as? Date == personalDate)
        for key in record.allKeys() {
            #expect((record[key] as? Date) != collegeDate, "plain \(key)")
            #expect((record.encryptedValues[key] as? Date) != collegeDate, "encrypted \(key)")
        }
    }

    @Test func coordinatorScansPeopleAndLogs() async throws {
        let stores = try EagarStores(location: .inMemory, models: [Person.self, ContactLog.self])
        let person = Person(displayName: "Seán", createdAt: now)
        let personName = person.personUUID.uuidString
        let log = ContactLog(personUUID: person.personUUID, occurredAt: now, createdAt: now)
        let logName = log.logUUID.uuidString
        try await stores.insert(person)
        try await stores.insert(log)
        let coordinator = try SyncCoordinator(
            store: stores.personal,
            adapters: [AnySyncAdapter(PersonSyncAdapter()), AnySyncAdapter(ContactLogSyncAdapter())],
            stateURL: nil
        )
        let changes = try await coordinator.scanLocalChanges()
        #expect(Set(changes) == [.save(recordName: personName), .save(recordName: logName)])
    }
}
