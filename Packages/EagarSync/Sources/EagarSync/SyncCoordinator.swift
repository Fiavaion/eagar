import CloudKit
import EagarCore
import EagarStore
import Foundation
import SwiftData

/// What needs to go to CloudKit.
public enum PendingChange: Sendable, Hashable {
    case save(recordName: String)
    case delete(recordName: String, recordType: String)
}

/// Per-record sync bookkeeping.
struct RecordState: Codable, Sendable, Equatable {
    var recordType: String
    /// The fields both sides last agreed on (the three-way merge base).
    var base: SyncFields
    var dataClass: DataClass
    /// The server record's system fields (change tag), archived.
    var systemFields: Data?
    /// When a local edit not yet confirmed by the server was first seen.
    var localEditedAt: Date?
}

/// Everything the coordinator persists between launches.
struct SyncStateFile: Codable, Sendable {
    var engineState: Data?
    var records: [String: RecordState] = [:]
}

/// The CloudKit-free core of PersonalStore sync (BD-02, PRD §7.5).
///
/// It scans the personal store for changes against each record's last-synced base, builds
/// CloudKit records for upload, and applies fetched records with a field-level three-way merge.
/// Applying a server change updates the base first, so the change is not echoed back.
public actor SyncCoordinator {
    private let store: ClassifiedStore
    private let adapters: [String: AnySyncAdapter]
    private let stateURL: URL?
    private let clock: any EagarClock
    private var state: SyncStateFile
    private let log = EagarLog(.store)

    /// - Parameters:
    ///   - store: must be PersonalStore; registration with `SyncRegistry` refuses CollegeStore.
    ///   - stateURL: where bookkeeping is persisted; `nil` keeps it in memory (tests).
    public init(store: ClassifiedStore, adapters: [AnySyncAdapter], stateURL: URL?, clock: any EagarClock = SystemClock()) throws(StoreError) {
        try SyncRegistry.register(store, engine: "CKSyncEngine")
        self.store = store
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.recordType, $0) })
        self.stateURL = stateURL
        self.clock = clock
        state = stateURL.flatMap { try? JSONDecoder().decode(SyncStateFile.self, from: Data(contentsOf: $0)) } ?? SyncStateFile()
    }

    // MARK: Engine state

    public var engineState: CKSyncEngine.State.Serialization? {
        state.engineState.flatMap { try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0) }
    }

    public func setEngineState(_ serialization: CKSyncEngine.State.Serialization) {
        state.engineState = try? JSONEncoder().encode(serialization)
        persist()
    }

    /// Forgets all bookkeeping, e.g. after the iCloud account changes. Local data is kept.
    public func reset() {
        state = SyncStateFile()
        persist()
    }

    // MARK: Outbound

    /// Compares the store with the last-synced bases and returns what must be sent.
    public func scanLocalChanges() async throws(SyncError) -> [PendingChange] {
        let adapters = Array(self.adapters.values)
        let snapshots: [(type: String, name: String, fields: SyncFields, dataClass: DataClass)]
        do {
            snapshots = try await store.perform { context in
                try adapters.flatMap { adapter in
                    try adapter.allSnapshots(context).map { (adapter.recordType, $0.recordName, $0.fields, $0.dataClass) }
                }
            }
        } catch {
            throw .storeFailed
        }
        let now = clock.now()
        var changes: [PendingChange] = []
        var seen = Set<String>()
        for snapshot in snapshots {
            // PersonalStore holds no college records; check anyway (defence in depth).
            guard snapshot.dataClass != .college else { continue }
            seen.insert(snapshot.name)
            if var existing = state.records[snapshot.name] {
                guard existing.base != snapshot.fields || existing.dataClass != snapshot.dataClass else { continue }
                existing.localEditedAt = existing.localEditedAt ?? now
                existing.dataClass = snapshot.dataClass
                state.records[snapshot.name] = existing
            } else {
                state.records[snapshot.name] = RecordState(recordType: snapshot.type, base: [:], dataClass: snapshot.dataClass, systemFields: nil, localEditedAt: now)
            }
            changes.append(.save(recordName: snapshot.name))
        }
        for (name, record) in state.records where !seen.contains(name) {
            changes.append(.delete(recordName: name, recordType: record.recordType))
        }
        persist()
        return changes
    }

    /// The CloudKit record to upload for `recordName`, carrying the last known change tag.
    public func record(for recordName: String) async -> CKRecord? {
        guard let entry = state.records[recordName], let adapter = adapters[entry.recordType] else { return nil }
        let fields: SyncFields?
        do {
            fields = try await store.perform { context in try adapter.localFields(recordName, context) }
        } catch {
            return nil
        }
        guard let fields else { return nil }
        let record = entry.systemFields.flatMap(Self.unarchive) ?? CKRecord(
            recordType: entry.recordType, recordID: CKRecord.ID(recordName: recordName, zoneID: SyncZone.id)
        )
        do {
            try RecordCodec.write(fields, dataClass: entry.dataClass, encrypted: adapter.encryptedFieldNames, into: record)
        } catch {
            return nil
        }
        return record
    }

    /// The server accepted `record`: it becomes the new base.
    public func didSave(_ record: CKRecord) {
        let name = record.recordID.recordName
        guard var entry = state.records[name], let adapter = adapters[entry.recordType],
              let read = try? RecordCodec.read(record, names: adapter.fieldNames, encrypted: adapter.encryptedFieldNames, bools: adapter.boolFieldNames)
        else { return }
        entry.base = read.fields
        entry.systemFields = Self.archive(record)
        entry.localEditedAt = nil
        state.records[name] = entry
        persist()
    }

    public func didDelete(recordName: String) {
        state.records[recordName] = nil
        persist()
    }

    // MARK: Inbound

    /// Applies a record fetched from CloudKit. If there is an unsent local edit, merges field by
    /// field; returns `true` when the merged result still has to be uploaded.
    @discardableResult
    public func apply(fetched record: CKRecord) async throws(SyncError) -> Bool {
        guard let adapter = adapters[record.recordType] else { throw .unknownRecordType }
        let name = record.recordID.recordName
        let previous = state.records[name]
        let server = try RecordCodec.read(record, names: adapter.fieldNames, encrypted: adapter.encryptedFieldNames, bools: adapter.boolFieldNames)

        let local: SyncFields?
        do {
            local = try await store.perform { context in try adapter.localFields(name, context) }
        } catch {
            throw .storeFailed
        }

        var result = server.fields
        var stillPending = false
        if let local, let previous, local != previous.base {
            result = ThreeWayMerge.merge(
                base: previous.base, local: local, server: server.fields,
                localEditedAt: previous.localEditedAt ?? clock.now(), serverModifiedAt: record.modificationDate
            )
            stillPending = result != server.fields
        }
        // Update the base before touching the store, so a later scan doesn't echo this change.
        state.records[name] = RecordState(
            recordType: record.recordType, base: server.fields, dataClass: server.dataClass,
            systemFields: Self.archive(record), localEditedAt: stillPending ? previous?.localEditedAt : nil
        )
        let merged = result
        let dataClass = server.dataClass
        do {
            try await store.perform { context in try adapter.upsert(name, merged, dataClass, context) }
        } catch {
            state.records[name] = previous
            throw .storeFailed
        }
        persist()
        return stillPending
    }

    /// Applies a deletion fetched from CloudKit.
    public func apply(deletedRecordName name: String, recordType: String) async throws(SyncError) {
        guard let adapter = adapters[recordType] else { throw .unknownRecordType }
        do {
            try await store.perform { context in try adapter.delete(name, context) }
        } catch {
            throw .storeFailed
        }
        state.records[name] = nil
        persist()
    }

    // MARK: Persistence

    func recordState(_ name: String) -> RecordState? { state.records[name] }

    private func persist() {
        guard let stateURL else { return }
        do {
            try FileManager.default.createDirectory(at: stateURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
        } catch {
            log.error("sync state could not be saved")
        }
    }

    static func archive(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    static func unarchive(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }
}
