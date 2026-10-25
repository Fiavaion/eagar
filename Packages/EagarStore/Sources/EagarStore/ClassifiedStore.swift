import EagarCore
import Foundation
import SwiftData

/// A persisted model that knows its data class. Every Eagar `@Model` conforms.
public typealias ClassifiedModel = PersistentModel & Classified

/// One of the two local stores, isolated to its own model executor.
///
/// Every save first checks that each inserted or changed model belongs in this store, so a
/// record whose class is changed after insertion, or a record inserted through `perform`,
/// still cannot be persisted in the wrong store.
public actor ClassifiedStore: ModelActor {
    public nonisolated let modelExecutor: any ModelExecutor
    public nonisolated let modelContainer: ModelContainer
    public nonisolated let kind: StoreKind

    private let log = EagarLog(.store)

    init(container: ModelContainer, kind: StoreKind) {
        modelContainer = container
        modelExecutor = DefaultSerialModelExecutor(modelContext: ModelContext(container))
        self.kind = kind
    }

    /// Inserts and saves `record`. Throws ``StoreError/classMismatch(store:dataClass:)``
    /// without persisting anything if the record's class belongs in the other store.
    public func insert<T: ClassifiedModel>(_ record: sending T) throws(StoreError) {
        try check(record.dataClass)
        modelContext.insert(record)
        try save()
    }

    /// Runs `body` against this store's context, then saves with the class check.
    /// Pending changes are rolled back if the check or the save fails.
    public func perform<R: Sendable>(_ body: (ModelContext) throws -> R) throws -> R {
        let result: R
        do {
            result = try body(modelContext)
        } catch {
            modelContext.rollback()
            throw error
        }
        try save()
        return result
    }

    /// Fetches and maps models to a `Sendable` value inside the actor.
    public func fetch<T: PersistentModel, R: Sendable>(
        _ descriptor: FetchDescriptor<T>,
        map: (T) -> R
    ) throws(StoreError) -> [R] {
        do {
            return try modelContext.fetch(descriptor).map(map)
        } catch {
            log.error("fetch failed in \(kind)")
            throw .fetchFailed(kind)
        }
    }

    /// Saves pending changes after verifying every pending model's class.
    public func save() throws(StoreError) {
        let pending = modelContext.insertedModelsArray + modelContext.changedModelsArray
        for model in pending {
            guard let classified = model as? any Classified else {
                // An unclassified model cannot prove it belongs here; treat it as college-or-worse.
                modelContext.rollback()
                throw .classMismatch(store: kind, dataClass: .college)
            }
            do {
                try check(classified.dataClass)
            } catch {
                modelContext.rollback()
                throw error
            }
        }
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            log.error("save failed in \(kind)")
            throw .saveFailed(kind)
        }
    }

    private func check(_ dataClass: DataClass) throws(StoreError) {
        guard StoreKind.placement(for: dataClass) == kind else {
            log.fault("refused \(dataClass) record in \(kind) store")
            throw .classMismatch(store: kind, dataClass: dataClass)
        }
    }
}
