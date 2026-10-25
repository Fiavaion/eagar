import EagarCore
import Foundation
import SwiftData

/// Where the stores live.
public enum StoreLocation: Sendable {
    /// Files under this directory: `Personal/personal.store` and `College/college.store`.
    case directory(URL)
    /// In memory, for previews and tests. Backup exclusion does not apply.
    case inMemory
}

/// The two stores and the router between them (BD-02, FR-CORE-02).
///
/// Model types come from several packages (the ledger, AI consent records, later domain
/// packages), so the app passes the full list in. The same type may live in both stores;
/// placement is decided per record by its data class.
public final class EagarStores: Sendable {
    public let personal: ClassifiedStore
    public let college: ClassifiedStore

    /// Opens or creates both stores. Both use `cloudKitDatabase: .none`; PersonalStore is
    /// synced only by Eagar's own CKSyncEngine layer (M1), and CollegeStore never is.
    public init(location: StoreLocation, models: [any PersistentModel.Type]) throws(StoreError) {
        let schema = Schema(models)
        personal = ClassifiedStore(
            container: try Self.container(.personal, schema: schema, location: location),
            kind: .personal
        )
        college = ClassifiedStore(
            container: try Self.container(.college, schema: schema, location: location),
            kind: .college
        )
    }

    /// The store a record of this class belongs in.
    public func store(for dataClass: DataClass) -> ClassifiedStore {
        StoreKind.placement(for: dataClass) == .college ? college : personal
    }

    /// The `StoreRouter` entry point: inserts `record` into the store its class belongs in.
    public func insert<T: ClassifiedModel>(_ record: sending T) async throws(StoreError) {
        let target = store(for: record.dataClass)
        try await target.insert(record)
    }

    /// The college store's directory; `nil` in memory.
    public static func collegeDirectory(in location: StoreLocation) -> URL? {
        guard case let .directory(root) = location else { return nil }
        return root.appending(path: "College", directoryHint: .isDirectory)
    }

    private static func container(
        _ kind: StoreKind,
        schema: Schema,
        location: StoreLocation
    ) throws(StoreError) -> ModelContainer {
        do {
            let configuration: ModelConfiguration
            switch location {
            case .inMemory:
                configuration = ModelConfiguration(
                    kind.rawValue, schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none
                )
            case let .directory(root):
                let directory = root.appending(
                    path: kind == .college ? "College" : "Personal", directoryHint: .isDirectory
                )
                try prepare(directory, for: kind)
                configuration = ModelConfiguration(
                    kind.rawValue,
                    schema: schema,
                    url: directory.appending(path: "\(kind.rawValue).store"),
                    cloudKitDatabase: .none
                )
            }
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            EagarLog(.store).fault("could not open \(kind) store")
            throw .setupFailed(kind)
        }
    }

    /// Creates the store directory. For CollegeStore, excludes the whole directory (and so the
    /// SQLite file and its -wal/-shm siblings) from iCloud and device backup, and sets Data
    /// Protection on iOS (BD-02, BD-04).
    private static func prepare(_ directory: URL, for kind: StoreKind) throws {
        var attributes: [FileAttributeKey: Any] = [:]
        #if os(iOS)
        if kind == .college {
            attributes[.protectionKey] = FileProtectionType.completeUntilFirstUserAuthentication
        }
        #endif
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: attributes
        )
        guard kind == .college else { return }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try url.setResourceValues(values)
    }
}
