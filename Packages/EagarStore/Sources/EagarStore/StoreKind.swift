import EagarCore

/// The two physically separate local stores (BD-02).
public enum StoreKind: String, Codable, Sendable, CaseIterable, LogSafe {
    /// Personal, public-content and approved-profile records. May be synced by CKSyncEngine (M1).
    case personal
    /// `college` records only. Never synced, excluded from backup.
    case college

    /// The store placement rule (PRD §7.3): college records go to CollegeStore, all others to PersonalStore.
    public static func placement(for dataClass: DataClass) -> StoreKind {
        dataClass == .college ? .college : .personal
    }

    public var logDescription: String { rawValue }
}

/// Errors from the store layer.
public enum StoreError: Error, Equatable, Sendable, LogSafe {
    /// A record's class does not belong in the store it was inserted into (FR-CORE-02).
    case classMismatch(store: StoreKind, dataClass: DataClass)
    /// The store files could not be created or protected.
    case setupFailed(StoreKind)
    /// SwiftData refused to save.
    case saveFailed(StoreKind)
    /// A fetch failed.
    case fetchFailed(StoreKind)
    /// A store tried to register with a sync engine it must never use (BD-02, B-4).
    case syncForbidden(StoreKind)

    public var logDescription: String {
        switch self {
        case let .classMismatch(store, dataClass): "classMismatch(\(store.rawValue), \(dataClass.rawValue))"
        case let .setupFailed(store): "setupFailed(\(store.rawValue))"
        case let .saveFailed(store): "saveFailed(\(store.rawValue))"
        case let .fetchFailed(store): "fetchFailed(\(store.rawValue))"
        case let .syncForbidden(store): "syncForbidden(\(store.rawValue))"
        }
    }
}
