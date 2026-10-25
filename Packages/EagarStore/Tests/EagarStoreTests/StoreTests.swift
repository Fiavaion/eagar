import EagarCore
import Foundation
import SwiftData
import Testing
@testable import EagarStore

@Model
final class TestNote: Classified {
    var dataClassRaw: String = DataClass.college.rawValue
    var sourceUUID: UUID?
    var text: String = ""

    init(_ dataClass: DataClass, text: String = "") {
        dataClassRaw = dataClass.rawValue
        self.text = text
    }

    var dataClass: DataClass { DataClass(rawValue: dataClassRaw) ?? .college }
    var sourceID: SourceID? { sourceUUID.map(SourceID.init) }
}

private func temporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory.appending(path: "eagar-store-\(UUID().uuidString)", directoryHint: .isDirectory)
}

private func count(_ store: ClassifiedStore) async throws -> Int {
    try await store.fetch(FetchDescriptor<TestNote>()) { _ in 1 }.count
}

@Suite(.serialized)
struct StoreTests {
    @Test func placementRule() {
        #expect(StoreKind.placement(for: .college) == .college)
        for dataClass in [DataClass.personal, .publicContent, .approvedProfile] {
            #expect(StoreKind.placement(for: dataClass) == .personal)
        }
    }

    /// B-3: a college record cannot enter PersonalStore, and a non-college record cannot enter CollegeStore.
    @Test func Boundary_B3_storeClassMismatchThrows() async throws {
        let stores = try EagarStores(location: .inMemory, models: [TestNote.self])

        await #expect(throws: StoreError.classMismatch(store: .personal, dataClass: .college)) {
            try await stores.personal.insert(TestNote(.college))
        }
        for dataClass in [DataClass.personal, .publicContent, .approvedProfile] {
            await #expect(throws: StoreError.classMismatch(store: .college, dataClass: dataClass)) {
                try await stores.college.insert(TestNote(dataClass))
            }
        }
        #expect(try await count(stores.personal) == 0)
        #expect(try await count(stores.college) == 0)
    }

    @Test func routerPlacesByClass() async throws {
        let stores = try EagarStores(location: .inMemory, models: [TestNote.self])
        try await stores.insert(TestNote(.college))
        try await stores.insert(TestNote(.personal))
        try await stores.insert(TestNote(.publicContent))
        #expect(try await count(stores.college) == 1)
        #expect(try await count(stores.personal) == 2)
    }

    /// Reclassifying a record to college after insert must not let it be saved in PersonalStore.
    @Test func Boundary_B3_reclassifiedRecordRefusedOnSave() async throws {
        let stores = try EagarStores(location: .inMemory, models: [TestNote.self])
        try await stores.personal.insert(TestNote(.personal))
        await #expect(throws: StoreError.classMismatch(store: .personal, dataClass: .college)) {
            try await stores.personal.perform { context in
                let note = try context.fetch(FetchDescriptor<TestNote>()).first!
                note.dataClassRaw = DataClass.college.rawValue
            }
        }
        let classes = try await stores.personal.fetch(FetchDescriptor<TestNote>()) { $0.dataClass }
        #expect(classes == [.personal])
    }

    @Test func insertThroughPerformIsChecked() async throws {
        let stores = try EagarStores(location: .inMemory, models: [TestNote.self])
        await #expect(throws: StoreError.self) {
            try await stores.personal.perform { context in context.insert(TestNote(.college)) }
        }
        #expect(try await count(stores.personal) == 0)
    }

    /// A throwing `perform` body leaves nothing pending that could poison the next save (verify finding).
    @Test func throwingPerformRollsBack() async throws {
        struct Abort: Error {}
        let stores = try EagarStores(location: .inMemory, models: [TestNote.self])
        await #expect(throws: Abort.self) {
            try await stores.personal.perform { context in
                context.insert(TestNote(.college))
                throw Abort()
            }
        }
        try await stores.personal.insert(TestNote(.personal))
        #expect(try await count(stores.personal) == 1)
    }

    @Test func unknownRawClassIsTreatedAsCollege() {
        let note = TestNote(.personal)
        note.dataClassRaw = "somethingNew"
        #expect(note.dataClass == .college)
    }

    /// B-4: CollegeStore files are excluded from backup and the store is never registered for sync.
    @Test func Boundary_B4_collegeStoreExcludedFromBackupAndSync() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let location = StoreLocation.directory(root)
        let stores = try EagarStores(location: location, models: [TestNote.self])
        try await stores.college.insert(TestNote(.college, text: "fixture"))

        let collegeDirectory = try #require(EagarStores.collegeDirectory(in: location))
        #expect(try collegeDirectory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
        let files = try FileManager.default.contentsOfDirectory(at: collegeDirectory, includingPropertiesForKeys: nil)
        #expect(files.contains { $0.lastPathComponent == "college.store" })
        for file in files {
            #expect(try file.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true,
                    "\(file.lastPathComponent) is not excluded from backup")
        }

        // No CloudKit mirroring on either container; Eagar's own engine handles PersonalStore (M1).
        for store in [stores.college, stores.personal] {
            for configuration in store.modelContainer.configurations {
                #expect(configuration.cloudKitContainerIdentifier == nil)
            }
        }

        SyncRegistry.reset()
        defer { SyncRegistry.reset() }
        #expect(throws: StoreError.syncForbidden(.college)) {
            try SyncRegistry.register(stores.college, engine: "CKSyncEngine")
        }
        try SyncRegistry.register(stores.personal, engine: "CKSyncEngine")
        #expect(SyncRegistry.registeredStores == [.personal])
    }

    @Test func personalStoreIsNotExcludedFromBackup() throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try EagarStores(location: .directory(root), models: [TestNote.self])
        let personal = root.appending(path: "Personal", directoryHint: .isDirectory)
        #expect(try personal.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == false)
    }
}
