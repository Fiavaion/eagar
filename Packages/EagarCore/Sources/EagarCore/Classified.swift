import Foundation

/// Opaque identifier of a data source (mail account, calendar, feed, contact set).
public struct SourceID: Hashable, Codable, Sendable, LogSafe {
    public let rawValue: UUID

    public init(_ rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }

    public var logDescription: String { rawValue.uuidString }
}

/// Anything that carries data of a known class (BD-03, FR-CORE-02).
///
/// Every persisted model conforms. The store layer refuses a record whose class does not
/// match the store it is inserted into. Conformances are never actor-isolated
/// (`SendableMetatype`), so the store and router actors can always read a record's class.
public protocol Classified: SendableMetatype {
    var dataClass: DataClass { get }
    /// The source the record came from; `nil` only for user-authored records.
    var sourceID: SourceID? { get }
}

/// How a source may be processed (BD-05).
public enum ProcessingMode: String, Codable, Sendable, CaseIterable, LogSafe {
    /// Deterministic rules only. No model call of any kind (invariant 3).
    case rulesOnly
    /// Apple on-device model and the Mac's local model.
    case localAI
    /// Local tiers plus Claude, per feature, with consent.
    case cloudAllowed

    public var logDescription: String { rawValue }
}

/// Whether a source or lane may ever reach the cloud. For Mark, `localOnly` sources produce
/// `college` data and `cloudAllowed` sources produce `personal` data (PRD Glossary).
public enum Boundary: String, Codable, Sendable, CaseIterable, LogSafe {
    case localOnly
    case cloudAllowed

    public var logDescription: String { rawValue }
}
