import CloudKit
import EagarCore
import EagarStore
import EagarSync
import Foundation
import SwiftData
import Testing
@testable import EagarCalendar

struct DeadlineSyncAdapterTests {
    @Test func fieldsRoundTripThroughACloudKitRecord() throws {
        let adapter = DeadlineSyncAdapter()
        let deadline = Deadline(title: "Renew car tax", dueAt: Date(timeIntervalSince1970: 1_800_000_000), isAllDay: true, reminderOffsetsMinutes: [1440, 60], dataClass: .personal, createdAt: Date(timeIntervalSince1970: 1_799_000_000))
        deadline.snooze(until: Date(timeIntervalSince1970: 1_799_500_000))
        deadline.mirrorOverride = true
        let fields = adapter.fields(of: deadline)
        #expect(Set(fields.keys) == adapter.fieldNames)

        let record = CKRecord(recordType: adapter.recordType, recordID: CKRecord.ID(recordName: adapter.recordName(of: deadline), zoneID: SyncZone.id))
        try RecordCodec.write(fields, dataClass: .personal, encrypted: adapter.encryptedFieldNames, into: record)
        let read = try RecordCodec.read(record, kinds: adapter.fieldKinds, encrypted: adapter.encryptedFieldNames)
        #expect(read.fields == fields)

        let copy = adapter.make(recordName: adapter.recordName(of: deadline), fields: read.fields, dataClass: read.dataClass)
        #expect(adapter.fields(of: copy) == fields)
        #expect(copy.deadlineUUID == deadline.deadlineUUID)
        #expect(copy.dataClass == .personal)
    }

    @Test func nullsClearOptionalFields() {
        let adapter = DeadlineSyncAdapter()
        let deadline = Deadline(title: "x", dueAt: Date(), dataClass: .personal, createdAt: Date())
        deadline.snooze(until: Date())
        adapter.apply(["snoozedUntil": .null, "completedAt": .null, "source": .null, "offsets": .ints([])], to: deadline)
        #expect(deadline.snoozedUntil == nil && deadline.completedAt == nil && deadline.sourceUUID == nil)
        #expect(deadline.reminderOffsetsMinutes.isEmpty)
    }

    /// Only personal deadlines sync: the coordinator runs on PersonalStore, so a college deadline
    /// (which lives in CollegeStore) is never scanned.
    @Test func Boundary_collegeDeadlinesAreNeverScanned() async throws {
        let stores = try EagarStores(location: .inMemory, models: [Deadline.self])
        try await stores.insert(Deadline(title: "Studio crit marks", dueAt: Date(), dataClass: .college, createdAt: Date()))
        let personal = Deadline(title: "Car tax", dueAt: Date(), dataClass: .personal, createdAt: Date())
        let personalName = personal.deadlineUUID.uuidString
        try await stores.insert(personal)
        let coordinator = try SyncCoordinator(store: stores.personal, adapters: [AnySyncAdapter(DeadlineSyncAdapter())], stateURL: nil)
        #expect(try await coordinator.scanLocalChanges() == [.save(recordName: personalName)])
    }
}
