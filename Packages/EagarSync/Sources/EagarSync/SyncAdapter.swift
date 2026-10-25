import EagarCore
import Foundation
import SwiftData

/// How one model type takes part in sync. Adapters are written beside the model (or in the app),
/// because EagarSync sits below the packages that define most models.
public protocol SyncAdapter: Sendable {
    associatedtype Model: PersistentModel & Classified

    /// CloudKit record type, e.g. `Deadline`.
    var recordType: String { get }
    /// Every synced field and its kind.
    var fieldKinds: [String: SyncFieldKind] { get }
    /// Fields stored in CloudKit `encryptedValues` (relationship notes, profile lines, payloads).
    var encryptedFieldNames: Set<String> { get }

    /// The stable record name: the model's own UUID string.
    func recordName(of model: Model) -> String
    func fields(of model: Model) -> SyncFields
    /// Every model of this type in the store.
    func all(in context: ModelContext) throws -> [Model]
    /// Finds the model with this record name, or nil.
    func find(recordName: String, in context: ModelContext) throws -> Model?
    /// Creates a model from server fields. It must have the given data class.
    func make(recordName: String, fields: SyncFields, dataClass: DataClass) -> Model
    /// Applies server fields to an existing model.
    func apply(_ fields: SyncFields, to model: Model)
}

extension SyncAdapter {
    public var fieldNames: Set<String> { Set(fieldKinds.keys) }
}

/// A type-erased adapter, so the engine can hold adapters for many model types.
public struct AnySyncAdapter: Sendable {
    public let recordType: String
    public let fieldKinds: [String: SyncFieldKind]
    public let encryptedFieldNames: Set<String>
    let upsert: @Sendable (String, SyncFields, DataClass, ModelContext) throws -> Void
    let delete: @Sendable (String, ModelContext) throws -> Void
    let localFields: @Sendable (String, ModelContext) throws -> SyncFields?
    let allSnapshots: @Sendable (ModelContext) throws -> [(recordName: String, fields: SyncFields, dataClass: DataClass)]

    public init<A: SyncAdapter>(_ adapter: A) {
        recordType = adapter.recordType
        fieldKinds = adapter.fieldKinds
        encryptedFieldNames = adapter.encryptedFieldNames
        upsert = { name, fields, dataClass, context in
            if let existing = try adapter.find(recordName: name, in: context) {
                adapter.apply(fields, to: existing)
            } else {
                context.insert(adapter.make(recordName: name, fields: fields, dataClass: dataClass))
            }
        }
        delete = { name, context in
            if let existing = try adapter.find(recordName: name, in: context) { context.delete(existing) }
        }
        localFields = { name, context in
            try adapter.find(recordName: name, in: context).map(adapter.fields(of:))
        }
        allSnapshots = { context in
            try adapter.all(in: context).map { (adapter.recordName(of: $0), adapter.fields(of: $0), $0.dataClass) }
        }
    }
}
