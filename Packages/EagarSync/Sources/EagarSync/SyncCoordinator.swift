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
    /// The fields both sides last agreed on (the three-way merge base). Empty for a record the
    /// server has never confirmed.
    var base: SyncFields
    var dataClass: DataClass
    /// The server record's system fields (change tag), archived.
    var systemFields: Data?
    /// When this device first saw a local edit not yet confirmed by the server.
    var localEditedAt: Date?
    /// Set when the record was deleted here and the server hasn't confirmed the deletion yet.
    var deletedAt: Date?
}

/// Everything the coordinator persists between launches.
struct SyncStateFile: Codable, Sendable {
    var engineState: Data?
    var records: [String: RecordState] = [:]
    /// Fetched records whose local apply failed, archived, to retry (verify finding).
    var pendingInbound: [String: Data] = [:]
    /// Set when the iCloud account signed out or changed; sync stays off until Mark confirms,
    /// so personal data is never uploaded to a different Apple ID automatically (D-018).
    var pausedForAccountChange = false
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
    /// - Throws: `StoreError.syncForbidden` for CollegeStore; `SyncError.stateFailed` when the
    ///   state file exists but cannot be read (sync must not start on an empty base then).
    public init(store: ClassifiedStore, adapters: [AnySyncAdapter], stateURL: URL?, clock: any EagarClock = SystemClock()) throws {
        try SyncRegistry.register(store, engine: "CKSyncEngine")
        self.store = store
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.recordType, $0) })
        self.stateURL = stateURL
        self.clock = clock
        state = try Self.loadState(from: stateURL)
    }

    /// Reads the state file. A missing file is a fresh start. A file that can't be read (for
    /// example while the device is locked) stops sync. A file that can't be parsed is moved
    /// aside, so it is never silently overwritten, and sync starts fresh.
    static func loadState(from url: URL?) throws -> SyncStateFile {
        guard let url, FileManager.default.fileExists(atPath: url.path) else { return SyncStateFile() }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            EagarLog(.store).error("sync state unreadable; sync not started")
            throw SyncError.stateFailed
        }
        do {
            return try JSONDecoder().decode(SyncStateFile.self, from: data)
        } catch {
            let aside = url.appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970))")
            try? FileManager.default.moveItem(at: url, to: aside)
            EagarLog(.store).fault("sync state corrupt; kept aside and starting fresh")
            return SyncStateFile()
        }
    }

    // MARK: Engine state

    /// The serialized `CKSyncEngine` state, if any.
    public var engineState: CKSyncEngine.State.Serialization? {
        guard let data = state.engineState else { return nil }
        do {
            return try JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: data)
        } catch {
            log.error("sync engine state unreadable; CloudKit will refetch")
            return nil
        }
    }

    /// Stores the latest `CKSyncEngine` state.
    public func setEngineState(_ serialization: CKSyncEngine.State.Serialization) {
        do {
            state.engineState = try JSONEncoder().encode(serialization)
            persist()
        } catch {
            log.error("sync engine state could not be encoded")
        }
    }

    /// Forgets all bookkeeping. Local data is kept.
    public func reset() {
        state = SyncStateFile()
        persist()
    }

    /// The iCloud account signed out or changed: forget bookkeeping and pause sync.
    public func accountChanged() {
        state = SyncStateFile()
        state.pausedForAccountChange = true
        persist()
    }

    /// Whether sync is paused until Mark confirms the current iCloud account.
    public var isPausedForAccountChange: Bool { state.pausedForAccountChange }

    /// Mark confirmed syncing with the current iCloud account.
    public func confirmAccount() {
        state.pausedForAccountChange = false
        persist()
    }

    /// Clears a record's change tag so the next save is treated as new (unknown item, zone
    /// recreated, encrypted-data key reset).
    public func clearSystemFields(recordName: String) {
        state.records[recordName]?.systemFields = nil
        persist()
    }

    /// Clears every change tag and base so every record is uploaded again (zone deleted or
    /// encrypted-data key reset, PRD §7.5).
    public func prepareFullReupload() {
        for name in state.records.keys {
            state.records[name]?.systemFields = nil
            state.records[name]?.base = [:]
        }
        persist()
    }

    // MARK: Outbound

    /// Compares the store with the last-synced bases and returns what must be sent.
    public func scanLocalChanges() async throws(SyncError) -> [PendingChange] {
        await retryPendingInbound()
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
                guard existing.base != snapshot.fields || existing.dataClass != snapshot.dataClass || existing.deletedAt != nil else { continue }
                existing.localEditedAt = existing.localEditedAt ?? now
                existing.dataClass = snapshot.dataClass
                existing.deletedAt = nil
                state.records[snapshot.name] = existing
            } else {
                state.records[snapshot.name] = RecordState(recordType: snapshot.type, base: [:], dataClass: snapshot.dataClass, systemFields: nil, localEditedAt: now)
            }
            changes.append(.save(recordName: snapshot.name))
        }
        for (name, record) in state.records where !seen.contains(name) {
            if record.deletedAt == nil { state.records[name]?.deletedAt = now }
            changes.append(.delete(recordName: name, recordType: record.recordType))
        }
        persist()
        return changes
    }

    /// The CloudKit record to upload for `recordName`, carrying the last known change tag, or
    /// `nil` if there is nothing to send (the caller should then drop the pending save).
    public func record(for recordName: String) async -> CKRecord? {
        guard let entry = state.records[recordName], entry.deletedAt == nil, let adapter = adapters[entry.recordType] else { return nil }
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
              let read = try? RecordCodec.read(record, kinds: adapter.fieldKinds, encrypted: adapter.encryptedFieldNames)
        else { return }
        entry.base = read.fields
        entry.systemFields = Self.archive(record)
        entry.localEditedAt = nil
        state.records[name] = entry
        persist()
    }

    /// The server confirmed a deletion.
    public func didDelete(recordName: String) {
        state.records[recordName] = nil
        persist()
    }

    // MARK: Inbound

    /// Applies a record fetched from CloudKit. With an unsent local edit (or no history at all,
    /// e.g. after an account change), merges field by field; returns `true` when the merged
    /// result still has to be uploaded.
    ///
    /// Read, merge and write happen in one store operation, so a concurrent app write can't be
    /// overwritten by a merge built from a stale read. A record deleted here but not yet
    /// confirmed is not resurrected, unless the server edit is newer than the deletion.
    @discardableResult
    public func apply(fetched record: CKRecord) async throws(SyncError) -> Bool {
        guard let adapter = adapters[record.recordType] else { throw .unknownRecordType }
        let name = record.recordID.recordName
        let previous = state.records[name]
        let server = try RecordCodec.read(record, kinds: adapter.fieldKinds, encrypted: adapter.encryptedFieldNames)

        if let deletedAt = previous?.deletedAt {
            let serverIsNewer = record.modificationDate.map { $0 > deletedAt } ?? false
            guard serverIsNewer else {
                // Keep the local deletion; it will be sent and win.
                state.records[name]?.systemFields = Self.archive(record)
                persist()
                return false
            }
        }

        let base = previous?.base ?? [:]
        let editedAt = previous?.localEditedAt ?? clock.now()
        let serverModified = record.modificationDate
        let serverFields = server.fields
        let dataClass = server.dataClass
        let result: (merged: SyncFields, stillPending: Bool)
        do {
            result = try await store.perform { context in
                let local = try adapter.localFields(name, context)
                var merged = serverFields
                var stillPending = false
                if let local, local != base {
                    merged = ThreeWayMerge.merge(base: base, local: local, server: serverFields, localEditedAt: editedAt, serverModifiedAt: serverModified)
                    stillPending = merged != serverFields
                }
                try adapter.upsert(name, merged, dataClass, context)
                return (merged, stillPending)
            }
        } catch {
            state.pendingInbound[name] = Self.archiveFull(record)
            persist()
            log.error("fetched change could not be applied; queued for retry")
            throw .storeFailed
        }
        state.pendingInbound[name] = nil
        state.records[name] = RecordState(
            recordType: record.recordType, base: serverFields, dataClass: dataClass,
            systemFields: Self.archive(record), localEditedAt: result.stillPending ? editedAt : nil
        )
        persist()
        return result.stillPending
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
        state.pendingInbound[name] = nil
        persist()
    }

    /// Retries fetched records whose apply failed earlier.
    func retryPendingInbound() async {
        for (name, data) in state.pendingInbound {
            guard let record = Self.unarchiveFull(data) else {
                state.pendingInbound[name] = nil
                continue
            }
            _ = try? await apply(fetched: record)
        }
    }

    // MARK: Persistence

    func recordState(_ name: String) -> RecordState? { state.records[name] }
    var pendingInboundCount: Int { state.pendingInbound.count }

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

    /// The whole record, values included, for the inbound retry queue (personal data only:
    /// college records are refused before they get here).
    static func archiveFull(_ record: CKRecord) -> Data {
        (try? NSKeyedArchiver.archivedData(withRootObject: record, requiringSecureCoding: true)) ?? Data()
    }

    static func unarchiveFull(_ data: Data) -> CKRecord? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKRecord.self, from: data)
    }
}
