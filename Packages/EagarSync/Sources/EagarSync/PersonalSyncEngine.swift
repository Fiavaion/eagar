import CloudKit
import EagarCore
import EagarStore
import Foundation
import Synchronization

/// Drives `CKSyncEngine` for PersonalStore (BD-02, PRD §7.5). All decisions live in
/// ``SyncCoordinator``; this type only translates between it and CloudKit.
///
/// CollegeStore can never reach here: ``SyncCoordinator`` registers with `SyncRegistry`, which
/// refuses it, and every record is re-checked when encoded.
public final class PersonalSyncEngine: CKSyncEngineDelegate, Sendable {
    public let coordinator: SyncCoordinator
    private let containerIdentifier: String
    private let engine = Mutex<CKSyncEngine?>(nil)
    private let log = EagarLog(.store)

    public init(containerIdentifier: String, coordinator: SyncCoordinator) {
        self.containerIdentifier = containerIdentifier
        self.coordinator = coordinator
    }

    /// Starts the engine and makes sure the custom zone exists. Needs the iCloud entitlement.
    /// Does nothing while sync is paused for an account change (see ``confirmAccountAndStart()``).
    public func start() async {
        guard await !coordinator.isPausedForAccountChange else {
            log.notice("personal sync paused until the iCloud account is confirmed")
            return
        }
        let database = CKContainer(identifier: containerIdentifier).privateCloudDatabase
        let configuration = CKSyncEngine.Configuration(
            database: database, stateSerialization: await coordinator.engineState, delegate: self
        )
        let engine = CKSyncEngine(configuration)
        engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncZone.id))])
        self.engine.withLock { $0 = engine }
        log.notice("personal sync started")
    }

    /// Mark confirmed the current iCloud account after a change: resume sync.
    public func confirmAccountAndStart() async {
        await coordinator.confirmAccount()
        await start()
        await syncLocalChanges()
    }

    /// Queues local changes found since the last sync. Call after writes and on launch.
    public func syncLocalChanges() async {
        guard let engine = engine.withLock({ $0 }) else { return }
        do {
            let changes = try await coordinator.scanLocalChanges()
            engine.state.add(pendingRecordZoneChanges: changes.map(Self.pending))
        } catch {
            log.error("sync scan failed: \(error)")
        }
    }

    /// Fetches and sends now (e.g. on pull to refresh).
    public func syncNow() async {
        guard let engine = engine.withLock({ $0 }) else { return }
        do {
            try await engine.fetchChanges()
            try await engine.sendChanges()
        } catch {
            log.error("sync round failed")
        }
    }

    // MARK: - CKSyncEngineDelegate

    public func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case let .stateUpdate(update):
            await coordinator.setEngineState(update.stateSerialization)

        case let .accountChange(change):
            switch change.changeType {
            case .signIn:
                break
            case .signOut, .switchAccounts:
                // Keep local data, forget bookkeeping and stop: never upload Mark's personal
                // records to a different Apple ID without his confirmation (D-018).
                await coordinator.accountChanged()
                engine.withLock { $0 = nil }
                log.notice("iCloud account changed; personal sync paused")
            @unknown default:
                break
            }

        case let .fetchedDatabaseChanges(changes):
            for deletion in changes.deletions where deletion.zoneID == SyncZone.id {
                // The zone was deleted or its encryption reset: re-upload everything from here.
                await coordinator.prepareFullReupload()
                syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncZone.id))])
                log.notice("personal zone removed on the server; re-uploading")
                await queueLocalChanges(on: syncEngine)
            }

        case let .fetchedRecordZoneChanges(changes):
            var reupload: [CKSyncEngine.PendingRecordZoneChange] = []
            for modification in changes.modifications {
                do {
                    if try await coordinator.apply(fetched: modification.record) {
                        reupload.append(.saveRecord(modification.record.recordID))
                    }
                } catch {
                    log.error("fetched record not applied: \(error)")
                }
            }
            for deletion in changes.deletions {
                do {
                    try await coordinator.apply(deletedRecordName: deletion.recordID.recordName, recordType: deletion.recordType)
                } catch {
                    log.error("fetched deletion not applied: \(error)")
                }
            }
            if !reupload.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: reupload) }

        case let .sentRecordZoneChanges(sent):
            for record in sent.savedRecords { await coordinator.didSave(record) }
            for id in sent.deletedRecordIDs { await coordinator.didDelete(recordName: id.recordName) }
            var retry: [CKSyncEngine.PendingRecordZoneChange] = []
            for failure in sent.failedRecordSaves {
                let id = failure.record.recordID
                switch failure.error.code {
                case .serverRecordChanged:
                    guard let server = failure.error.serverRecord else {
                        log.error("conflict without a server record; clearing the change tag and retrying")
                        await coordinator.clearSystemFields(recordName: id.recordName)
                        retry.append(.saveRecord(id))
                        continue
                    }
                    do {
                        if try await coordinator.apply(fetched: server) { retry.append(.saveRecord(id)) }
                    } catch {
                        log.error("conflict could not be merged: \(error)")
                    }
                case .unknownItem, .userDeletedZone:
                    // Deleted on the server: upload ours as a new record.
                    await coordinator.clearSystemFields(recordName: id.recordName)
                    retry.append(.saveRecord(id))
                case .zoneNotFound:
                    await coordinator.clearSystemFields(recordName: id.recordName)
                    syncEngine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: SyncZone.id))])
                    retry.append(.saveRecord(id))
                case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                    retry.append(.saveRecord(id))
                default:
                    log.error("record save failed with CloudKit code \(failure.error.code.rawValue); not retried")
                }
            }
            for (id, error) in sent.failedRecordDeletes {
                switch error.code {
                case .unknownItem:
                    await coordinator.didDelete(recordName: id.recordName) // already gone
                case .networkFailure, .networkUnavailable, .serviceUnavailable, .requestRateLimited, .zoneBusy:
                    retry.append(.deleteRecord(id))
                default:
                    log.error("record delete failed with CloudKit code \(error.code.rawValue); not retried")
                }
            }
            if !retry.isEmpty { syncEngine.state.add(pendingRecordZoneChanges: retry) }

        default:
            break
        }
    }

    public func nextRecordZoneChangeBatch(_ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { context.options.scope.contains($0) }
        let coordinator = self.coordinator
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { id in
            let record = await coordinator.record(for: id.recordName)
            if record == nil {
                // Nothing to send (deleted since, or state reset): drop it so it isn't retried forever.
                syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(id)])
            }
            return record
        }
    }

    private func queueLocalChanges(on syncEngine: CKSyncEngine) async {
        do {
            let changes = try await coordinator.scanLocalChanges()
            syncEngine.state.add(pendingRecordZoneChanges: changes.map(Self.pending))
        } catch {
            log.error("sync scan failed: \(error)")
        }
    }

    static func pending(_ change: PendingChange) -> CKSyncEngine.PendingRecordZoneChange {
        switch change {
        case let .save(name): .saveRecord(CKRecord.ID(recordName: name, zoneID: SyncZone.id))
        case let .delete(name, _): .deleteRecord(CKRecord.ID(recordName: name, zoneID: SyncZone.id))
        }
    }
}
