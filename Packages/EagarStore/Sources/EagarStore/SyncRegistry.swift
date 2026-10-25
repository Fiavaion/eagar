import EagarCore
import Synchronization

/// The single gate through which a sync engine attaches to a store (BD-02, B-4).
///
/// `EagarSync` (M1) must call ``register(_:engine:)`` before driving a CKSyncEngine for a
/// store. CollegeStore is refused, so there is no code path that syncs college records.
public enum SyncRegistry {
    private static let registrations = Mutex<[StoreKind: String]>([:])

    /// Records that `engine` syncs `store`. Throws for CollegeStore.
    public static func register(_ store: ClassifiedStore, engine: String) throws(StoreError) {
        guard store.kind == .personal else {
            EagarLog(.store).fault("refused sync registration for \(store.kind)")
            throw .syncForbidden(store.kind)
        }
        registrations.withLock { $0[store.kind] = engine }
    }

    /// The stores currently registered with a sync engine.
    public static var registeredStores: Set<StoreKind> {
        registrations.withLock { Set($0.keys) }
    }

    /// Clears registrations. Tests only.
    static func reset() {
        registrations.withLock { $0.removeAll() }
    }
}
