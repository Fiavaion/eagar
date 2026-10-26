import CloudKit
import EagarCore
import EagarStore
import EagarSync
import Foundation
import SwiftData
import Testing
@testable import EagarMoney

struct TrialSyncAdapterTests {
    @Test func fieldsRoundTripThroughACloudKitRecord() throws {
        let adapter = TrialSyncAdapter()
        let trial = Trial(
            service: "Audible", price: Decimal(string: "8.99")!, currencyCode: "GBP", period: .yearly, isTrial: false,
            startedAt: Date(timeIntervalSince1970: 1_799_000_000), renewsAt: Date(timeIntervalSince1970: 1_800_000_000),
            cancelURL: URL(string: "https://www.example.com/cancel"), safetyMarginDays: 3, reminderDays: [5, 1],
            dataClass: .personal, sourceID: SourceID(), createdAt: Date(timeIntervalSince1970: 1_798_000_000)
        )
        trial.confirmCancelled(at: Date(timeIntervalSince1970: 1_799_500_000))
        let fields = adapter.fields(of: trial)
        #expect(Set(fields.keys) == adapter.fieldNames)

        let record = CKRecord(recordType: adapter.recordType, recordID: CKRecord.ID(recordName: adapter.recordName(of: trial), zoneID: SyncZone.id))
        try RecordCodec.write(fields, dataClass: .personal, encrypted: adapter.encryptedFieldNames, into: record)
        let read = try RecordCodec.read(record, kinds: adapter.fieldKinds, encrypted: adapter.encryptedFieldNames)
        #expect(read.fields == fields)

        let copy = adapter.make(recordName: adapter.recordName(of: trial), fields: read.fields, dataClass: read.dataClass)
        #expect(adapter.fields(of: copy) == fields)
        #expect(copy.trialUUID == trial.trialUUID)
        #expect(copy.dataClass == .personal)
        #expect(copy.snapshot == trial.snapshot)
    }

    @Test func priceIsLocaleIndependentAndExact() {
        #expect(TrialSyncAdapter.encode(Decimal(string: "1234.5")!) == "1234.5")
        #expect(TrialSyncAdapter.decode("0.1") == Decimal(string: "0.1"))
        let trial = Trial(service: "x", price: 7, renewsAt: .now, createdAt: .now)
        TrialSyncAdapter().apply(["price": .string("not a number")], to: trial)
        #expect(trial.price == 7)
    }

    @Test func nullsClearOptionalFields() {
        let adapter = TrialSyncAdapter()
        let trial = Trial(service: "x", price: 1, startedAt: .now, renewsAt: .now, cancelURL: URL(string: "https://a.example"), sourceID: SourceID(), createdAt: .now)
        trial.confirmCancelled(at: .now)
        adapter.apply(["startedAt": .null, "cancelURL": .null, "source": .null, "cancelledAt": .null, "reminderDays": .ints([])], to: trial)
        #expect(trial.startedAt == nil && trial.cancelURLString == nil && trial.sourceUUID == nil && trial.cancelledAt == nil)
        #expect(trial.reminderDays.isEmpty)
    }

    @Test func findIgnoresMalformedRecordNames() throws {
        let container = try ModelContainer(for: Trial.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        #expect(try TrialSyncAdapter().find(recordName: "not-a-uuid", in: ModelContext(container)) == nil)
    }

    /// Only personal trials sync: the coordinator runs on PersonalStore, so a college-class
    /// trial (placed in CollegeStore) is never scanned.
    @Test func Boundary_collegeTrialsAreNeverScanned() async throws {
        let stores = try EagarStores(location: .inMemory, models: [Trial.self])
        try await stores.insert(Trial(service: "College licence", price: 1, renewsAt: .now, dataClass: .college, createdAt: .now))
        let personal = Trial(service: "Spotify", price: 1, renewsAt: .now, createdAt: .now)
        let personalName = personal.trialUUID.uuidString
        try await stores.insert(personal)
        let coordinator = try SyncCoordinator(store: stores.personal, adapters: [AnySyncAdapter(TrialSyncAdapter())], stateURL: nil)
        #expect(try await coordinator.scanLocalChanges() == [.save(recordName: personalName)])
    }
}
