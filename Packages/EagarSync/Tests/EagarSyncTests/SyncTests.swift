import CloudKit
import EagarCore
import EagarStore
import Foundation
import SwiftData
import Synchronization
import Testing
@testable import EagarSync

@Model
final class Note: Classified {
    var noteUUID: UUID = UUID()
    var title: String = ""
    var count: Int = 0
    var done: Bool = false
    var secret: String = ""
    var tags: [Int] = []
    var dataClassRaw: String = DataClass.personal.rawValue

    init(_ title: String, dataClass: DataClass = .personal, uuid: UUID = UUID()) {
        self.title = title
        noteUUID = uuid
        dataClassRaw = dataClass.rawValue
    }

    var dataClass: DataClass { DataClass(rawValue: dataClassRaw) ?? .college }
    var sourceID: SourceID? { nil }
}

struct NoteAdapter: SyncAdapter {
    let recordType = "Note"
    let fieldKinds: [String: SyncFieldKind] = ["title": .string, "count": .int, "done": .bool, "secret": .string, "tags": .ints]
    let encryptedFieldNames: Set<String> = ["secret"]
    /// Lookups of these record names throw, to exercise the inbound retry queue. Scoped to
    /// names so parallel tests are unaffected.
    static let failingNames = Mutex<Set<String>>([])
    struct InjectedFailure: Error {}

    func recordName(of model: Note) -> String { model.noteUUID.uuidString }
    func fields(of model: Note) -> SyncFields {
        ["title": .string(model.title), "count": .int(Int64(model.count)), "done": .bool(model.done), "secret": .string(model.secret), "tags": .ints(model.tags.map(Int64.init))]
    }
    func all(in context: ModelContext) throws -> [Note] { try context.fetch(FetchDescriptor<Note>()) }
    func find(recordName: String, in context: ModelContext) throws -> Note? {
        if Self.failingNames.withLock({ $0.contains(recordName) }) { throw InjectedFailure() }
        guard let uuid = UUID(uuidString: recordName) else { return nil }
        return try context.fetch(FetchDescriptor<Note>(predicate: #Predicate { $0.noteUUID == uuid })).first
    }
    func make(recordName: String, fields: SyncFields, dataClass: DataClass) -> Note {
        let note = Note("", dataClass: dataClass, uuid: UUID(uuidString: recordName) ?? UUID())
        apply(fields, to: note)
        return note
    }
    func apply(_ fields: SyncFields, to model: Note) {
        if case let .string(v)? = fields["title"] { model.title = v }
        if case let .int(v)? = fields["count"] { model.count = Int(v) }
        if case let .bool(v)? = fields["done"] { model.done = v }
        if case let .string(v)? = fields["secret"] { model.secret = v }
        if case let .ints(v)? = fields["tags"] { model.tags = v.map { Int($0) } }
    }
}

struct TestClock: EagarClock {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { date }
}

private func setUp(stateURL: URL? = nil) throws -> (EagarStores, SyncCoordinator) {
    let stores = try EagarStores(location: .inMemory, models: [Note.self])
    let coordinator = try SyncCoordinator(store: stores.personal, adapters: [AnySyncAdapter(NoteAdapter())], stateURL: stateURL, clock: TestClock())
    return (stores, coordinator)
}

private func serverRecord(_ uuid: UUID, title: String, count: Int64 = 0, done: Bool = false, secret: String = "", dataClass: DataClass = .personal) throws -> CKRecord {
    let record = CKRecord(recordType: "Note", recordID: CKRecord.ID(recordName: uuid.uuidString, zoneID: SyncZone.id))
    record[syncDataClassField] = dataClass.rawValue
    record["title"] = title
    record["count"] = count
    record["done"] = done ? Int64(1) : Int64(0)
    record.encryptedValues["secret"] = secret
    return record
}

private func titles(_ stores: EagarStores) async throws -> [String] {
    try await stores.personal.fetch(FetchDescriptor<Note>(sortBy: [SortDescriptor(\.title)])) { $0.title }
}

struct RecordCodecTests {
    @Test func roundTripWithEncryptedFields() throws {
        let record = CKRecord(recordType: "Note", recordID: CKRecord.ID(recordName: "n", zoneID: SyncZone.id))
        let fields: SyncFields = ["title": .string("Car tax"), "count": .int(3), "done": .bool(true), "secret": .string("note"), "tags": .ints([])]
        try RecordCodec.write(fields, dataClass: .personal, encrypted: ["secret"], into: record)
        #expect(record["secret"] == nil) // only in encryptedValues
        #expect(record.encryptedValues["secret"] as? String == "note")
        let read = try RecordCodec.read(record, kinds: NoteAdapter().fieldKinds, encrypted: ["secret"])
        #expect(read.fields == fields)
        #expect(read.dataClass == .personal)
    }

    /// B-4 (sync half) / B-8: a college record can never be encoded for, or accepted from, CloudKit.
    @Test func Boundary_B4_collegeRecordsNeverEncodedOrAccepted() throws {
        let record = CKRecord(recordType: "Note", recordID: CKRecord.ID(recordName: "n", zoneID: SyncZone.id))
        #expect(throws: SyncError.collegeRecordRefused) {
            try RecordCodec.write(["title": .string("Studio crit")], dataClass: .college, encrypted: [], into: record)
        }
        #expect(record["title"] == nil)
        let unlabelled = CKRecord(recordType: "Note", recordID: CKRecord.ID(recordName: "m", zoneID: SyncZone.id))
        unlabelled["title"] = "no class"
        #expect(throws: SyncError.collegeRecordRefused) { try RecordCodec.read(unlabelled, kinds: ["title": .string], encrypted: []) }
    }

    @Test func valueConversionsFollowTheDeclaredKind() {
        #expect(SyncValue.from(nil, kind: .string) == .null)
        #expect(SyncValue.from(NSNumber(value: 2.5), kind: .double) == .double(2.5))
        #expect(SyncValue.from(NSNumber(value: 7), kind: .int) == .int(7))
        #expect(SyncValue.from(NSNumber(value: 1), kind: .bool) == .bool(true))
        #expect(SyncValue.from(["a"], kind: .strings) == .strings(["a"]))
        #expect(SyncValue.from([Int64(1)], kind: .ints) == .ints([1]))
        #expect(SyncValue.from(Data([1]), kind: .data) == .data(Data([1])))
        #expect(SyncValue.from(Date(timeIntervalSince1970: 5), kind: .date) == .date(Date(timeIntervalSince1970: 5)))
        #expect(SyncValue.from("wrong kind", kind: .int) == .null)
        // Verify finding: an empty list, or a missing one, reads as an empty list of the right kind.
        #expect(SyncValue.from([String](), kind: .ints) == .ints([]))
        #expect(SyncValue.from(nil, kind: .ints) == .ints([]))
        #expect(SyncValue.from(nil, kind: .strings) == .strings([]))
    }
}

struct ThreeWayMergeTests {
    private let base: SyncFields = ["title": .string("A"), "count": .int(1)]
    private let t0 = Date(timeIntervalSince1970: 1_000)

    /// M1 acceptance: conflict tests for concurrent edits.
    @Test func concurrentEditsToDifferentFieldsBothSurvive() {
        let merged = ThreeWayMerge.merge(base: base, local: ["title": .string("B"), "count": .int(1)], server: ["title": .string("A"), "count": .int(5)], localEditedAt: t0, serverModifiedAt: t0 + 10)
        #expect(merged == ["title": .string("B"), "count": .int(5)])
    }

    @Test func sameFieldLaterEditWins() {
        let local: SyncFields = ["title": .string("Local"), "count": .int(1)]
        let server: SyncFields = ["title": .string("Server"), "count": .int(1)]
        #expect(ThreeWayMerge.merge(base: base, local: local, server: server, localEditedAt: t0, serverModifiedAt: t0 + 10)["title"] == .string("Server"))
        #expect(ThreeWayMerge.merge(base: base, local: local, server: server, localEditedAt: t0 + 10, serverModifiedAt: t0)["title"] == .string("Local"))
        #expect(ThreeWayMerge.merge(base: base, local: local, server: server, localEditedAt: t0, serverModifiedAt: nil)["title"] == .string("Local"))
    }

    @Test func identicalChangesAndUnchangedFields() {
        let same: SyncFields = ["title": .string("Z"), "count": .int(1)]
        #expect(ThreeWayMerge.merge(base: base, local: same, server: same, localEditedAt: t0, serverModifiedAt: t0) == same)
        #expect(ThreeWayMerge.merge(base: base, local: base, server: base, localEditedAt: t0, serverModifiedAt: t0) == base)
        #expect(ThreeWayMerge.changedFields(from: base, to: same) == ["title"])
    }

    @Test(arguments: 0..<200)
    func mergedFieldsAlwaysComeFromOneSide(seed: Int) {
        var rng = SystemRandomNumberGenerator()
        let values: [SyncValue] = [.string("a"), .string("b"), .int(1), .null]
        let names = ["x", "y", "z"]
        func pick() -> SyncFields { Dictionary(uniqueKeysWithValues: names.map { ($0, values.randomElement(using: &rng)!) }) }
        let (b, l, s) = (pick(), pick(), pick())
        let merged = ThreeWayMerge.merge(base: b, local: l, server: s, localEditedAt: t0, serverModifiedAt: t0 + Double(seed % 3) - 1)
        for name in names {
            #expect(merged[name] == l[name] || merged[name] == s[name])
            if l[name] == b[name] { #expect(merged[name] == s[name]) }
            if s[name] == b[name] { #expect(merged[name] == l[name]) }
        }
    }
}

struct SyncCoordinatorTests {
    /// B-4: the sync engine can attach to PersonalStore only.
    @Test func Boundary_B4_coordinatorRefusesCollegeStore() throws {
        let stores = try EagarStores(location: .inMemory, models: [Note.self])
        #expect(throws: StoreError.syncForbidden(.college)) {
            try SyncCoordinator(store: stores.college, adapters: [AnySyncAdapter(NoteAdapter())], stateURL: nil)
        }
        _ = try SyncCoordinator(store: stores.personal, adapters: [AnySyncAdapter(NoteAdapter())], stateURL: nil)
        #expect(!SyncRegistry.registeredStores.contains(.college))
    }

    @Test func newLocalRecordIsSentThenSettles() async throws {
        let (stores, coordinator) = try setUp()
        let note = Note("Car tax")
        let uuid = note.noteUUID
        try await stores.personal.insert(note)
        #expect(try await coordinator.scanLocalChanges() == [.save(recordName: uuid.uuidString)])

        let record = try #require(await coordinator.record(for: uuid.uuidString))
        #expect(record["title"] as? String == "Car tax")
        #expect(record[syncDataClassField] as? String == "personal")
        await coordinator.didSave(record)
        #expect(try await coordinator.scanLocalChanges().isEmpty)
    }

    @Test func localEditAndDeletionAreDetected() async throws {
        let (stores, coordinator) = try setUp()
        let note = Note("Car tax")
        let name = note.noteUUID.uuidString
        try await stores.personal.insert(note)
        _ = try await coordinator.scanLocalChanges()
        await coordinator.didSave(try #require(await coordinator.record(for: name)))

        try await stores.personal.perform { context in
            try context.fetch(FetchDescriptor<Note>()).first!.count = 2
        }
        #expect(try await coordinator.scanLocalChanges() == [.save(recordName: name)])
        #expect(await coordinator.recordState(name)?.localEditedAt == TestClock().date)

        try await stores.personal.perform { context in
            try context.fetch(FetchDescriptor<Note>()).forEach(context.delete)
        }
        #expect(try await coordinator.scanLocalChanges() == [.delete(recordName: name, recordType: "Note")])
        await coordinator.didDelete(recordName: name)
        #expect(try await coordinator.scanLocalChanges().isEmpty)
    }

    @Test func fetchedRecordIsAppliedWithoutEcho() async throws {
        let (stores, coordinator) = try setUp()
        let uuid = UUID()
        let pending = try await coordinator.apply(fetched: serverRecord(uuid, title: "From iPad", count: 4, done: true, secret: "encrypted"))
        #expect(!pending)
        #expect(try await titles(stores) == ["From iPad"])
        let applied = try await stores.personal.fetch(FetchDescriptor<Note>()) { ($0.done, $0.secret, $0.count) }
        #expect(applied.first?.0 == true && applied.first?.1 == "encrypted" && applied.first?.2 == 4)
        #expect(try await coordinator.scanLocalChanges().isEmpty) // no echo

        try await coordinator.apply(deletedRecordName: uuid.uuidString, recordType: "Note")
        #expect(try await titles(stores).isEmpty)
    }

    /// M1 acceptance: concurrent edits on two devices merge field by field.
    @Test func concurrentEditMergesAndReuploads() async throws {
        let (stores, coordinator) = try setUp()
        let note = Note("Car tax")
        let uuid = note.noteUUID
        try await stores.personal.insert(note)
        _ = try await coordinator.scanLocalChanges()
        await coordinator.didSave(try #require(await coordinator.record(for: uuid.uuidString)))

        // This device edits the title; another device changed the count meanwhile.
        try await stores.personal.perform { context in try context.fetch(FetchDescriptor<Note>()).first!.title = "Renew car tax" }
        _ = try await coordinator.scanLocalChanges()
        let stillPending = try await coordinator.apply(fetched: serverRecord(uuid, title: "Car tax", count: 9))
        #expect(stillPending)
        let merged = try await stores.personal.fetch(FetchDescriptor<Note>()) { ($0.title, $0.count) }
        #expect(merged.first?.0 == "Renew car tax")
        #expect(merged.first?.1 == 9)
        #expect(try await coordinator.scanLocalChanges() == [.save(recordName: uuid.uuidString)])
        let upload = try #require(await coordinator.record(for: uuid.uuidString))
        #expect(upload["title"] as? String == "Renew car tax")
        #expect(upload["count"] as? Int64 == 9)
    }

    /// B-4 (sync half, partial; the full B-8 end-to-end test arrives with cdbooking in M2): a
    /// college record arriving from CloudKit is refused and never inserted.
    @Test func Boundary_B4_collegeRecordFromCloudIsRefused() async throws {
        let (stores, coordinator) = try setUp()
        await #expect(throws: SyncError.collegeRecordRefused) {
            try await coordinator.apply(fetched: serverRecord(UUID(), title: "NCAD meeting", dataClass: .college))
        }
        #expect(try await titles(stores).isEmpty)
        let collegeCount = try await stores.college.fetch(FetchDescriptor<Note>()) { _ in 1 }.count
        #expect(collegeCount == 0)
    }

    @Test func unknownRecordTypeIsRejected() async throws {
        let (_, coordinator) = try setUp()
        let record = CKRecord(recordType: "Mystery", recordID: CKRecord.ID(recordName: "x", zoneID: SyncZone.id))
        await #expect(throws: SyncError.unknownRecordType) { try await coordinator.apply(fetched: record) }
    }

    @Test func stateSurvivesRelaunch() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "eagar-sync-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let stores = try EagarStores(location: .inMemory, models: [Note.self])
        let note = Note("Car tax")
        let name = note.noteUUID.uuidString
        try await stores.personal.insert(note)
        let first = try SyncCoordinator(store: stores.personal, adapters: [AnySyncAdapter(NoteAdapter())], stateURL: url, clock: TestClock())
        _ = try await first.scanLocalChanges()
        await first.didSave(try #require(await first.record(for: name)))

        let second = try SyncCoordinator(store: stores.personal, adapters: [AnySyncAdapter(NoteAdapter())], stateURL: url, clock: TestClock())
        #expect(try await second.scanLocalChanges().isEmpty)
        #expect(await second.recordState(name)?.systemFields != nil)
        await second.reset()
        #expect(try await second.scanLocalChanges().count == 1)
    }
}

/// Regression tests for the M1 sync review findings.
@Suite(.serialized)
struct SyncReviewRegressionTests {
    /// An empty list must settle after a save, not re-upload forever.
    @Test func emptyListSettles() async throws {
        let (stores, coordinator) = try setUp()
        let note = Note("No tags")
        let name = note.noteUUID.uuidString
        try await stores.personal.insert(note)
        _ = try await coordinator.scanLocalChanges()
        let record = try #require(await coordinator.record(for: name))
        record["tags"] = nil // CloudKit may return an empty list as missing
        await coordinator.didSave(record)
        #expect(try await coordinator.scanLocalChanges().isEmpty)
    }

    /// After an account change or lost state, a fetched record must not overwrite a local edit.
    @Test func noHistoryMergeKeepsLocalEdits() async throws {
        let (stores, coordinator) = try setUp()
        let note = Note("New local edit")
        let uuid = note.noteUUID
        try await stores.personal.insert(note)
        await coordinator.reset()
        let pending = try await coordinator.apply(fetched: serverRecord(uuid, title: "Old"))
        #expect(pending)
        #expect(try await titles(stores) == ["New local edit"])
        #expect(try await coordinator.scanLocalChanges() == [.save(recordName: uuid.uuidString)])
    }

    /// A deletion made here is not undone by an older edit arriving from the server.
    @Test func deletedRecordIsNotResurrected() async throws {
        let (stores, coordinator) = try setUp()
        let note = Note("To delete")
        let uuid = note.noteUUID
        try await stores.personal.insert(note)
        _ = try await coordinator.scanLocalChanges()
        await coordinator.didSave(try #require(await coordinator.record(for: uuid.uuidString)))
        try await stores.personal.perform { context in try context.fetch(FetchDescriptor<Note>()).forEach(context.delete) }
        #expect(try await coordinator.scanLocalChanges() == [.delete(recordName: uuid.uuidString, recordType: "Note")])

        // An offline record has no modification date, so it can't be newer than the deletion.
        let pending = try await coordinator.apply(fetched: serverRecord(uuid, title: "Edited elsewhere"))
        #expect(!pending)
        #expect(try await titles(stores).isEmpty)
        #expect(await coordinator.record(for: uuid.uuidString) == nil)
        #expect(try await coordinator.scanLocalChanges() == [.delete(recordName: uuid.uuidString, recordType: "Note")])
    }

    @Test func corruptStateFileIsKeptAsideNotOverwritten() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "eagar-sync-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "state.json")
        try Data("not json".utf8).write(to: url)
        let stores = try EagarStores(location: .inMemory, models: [Note.self])
        _ = try SyncCoordinator(store: stores.personal, adapters: [AnySyncAdapter(NoteAdapter())], stateURL: url)
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.contains { $0.hasPrefix("state.json.corrupt-") })
        #expect(!files.contains("state.json"))
    }

    @Test func unreadableStateFileStopsSync() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "eagar-sync-\(UUID().uuidString)")
        let url = directory.appending(path: "state.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) // a directory can't be read as data
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: SyncError.stateFailed) { try SyncCoordinator.loadState(from: url) }
    }

    /// A fetched change whose local write fails is queued and applied on the next scan.
    @Test func failedInboundApplyIsRetried() async throws {
        let (stores, coordinator) = try setUp()
        let uuid = UUID()
        NoteAdapter.failingNames.withLock { _ = $0.insert(uuid.uuidString) }
        await #expect(throws: SyncError.storeFailed) { try await coordinator.apply(fetched: serverRecord(uuid, title: "From iPad")) }
        #expect(await coordinator.pendingInboundCount == 1)
        NoteAdapter.failingNames.withLock { _ = $0.remove(uuid.uuidString) }
        _ = try await coordinator.scanLocalChanges()
        #expect(try await titles(stores) == ["From iPad"])
        #expect(await coordinator.pendingInboundCount == 0)
    }

    @Test func accountChangePausesSyncUntilConfirmed() async throws {
        let (_, coordinator) = try setUp()
        await coordinator.accountChanged()
        #expect(await coordinator.isPausedForAccountChange)
        await coordinator.confirmAccount()
        #expect(await !coordinator.isPausedForAccountChange)
    }
}
