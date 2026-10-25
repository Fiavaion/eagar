import CloudKit
import EagarCore
import Foundation

/// The declared kind of a synced field. Decoding uses it, because CloudKit stores booleans as
/// integers and cannot tell an empty string list from an empty integer list.
public enum SyncFieldKind: String, Sendable, Hashable, Codable {
    case string, int, double, bool, date, data, strings, ints
}

/// A field value that can travel in a CloudKit record. Covers what Eagar's models use.
public enum SyncValue: Sendable, Hashable, Codable {
    case string(String)
    case int(Int64)
    case double(Double)
    case bool(Bool)
    case date(Date)
    case data(Data)
    case strings([String])
    case ints([Int64])
    case null

    /// CloudKit's representation. Bools travel as integers.
    var recordValue: (any CKRecordValueProtocol)? {
        switch self {
        case let .string(value): value
        case let .int(value): value
        case let .double(value): value
        case let .bool(value): value ? Int64(1) : Int64(0)
        case let .date(value): value
        case let .data(value): value
        case let .strings(value): value
        case let .ints(value): value
        case .null: nil
        }
    }

    /// Reads a CloudKit value as the declared `kind`. A missing list reads as an empty list (CloudKit
    /// may return either), so an empty list never looks like a change. Anything that doesn't fit
    /// the kind reads as `.null`.
    static func from(_ value: Any?, kind: SyncFieldKind) -> SyncValue {
        switch kind {
        case .strings: return .strings((value as? [String]) ?? [])
        case .ints: return .ints((value as? [Any])?.compactMap { ($0 as? NSNumber)?.int64Value } ?? [])
        default: break
        }
        guard let value else { return .null }
        switch (kind, value) {
        case let (.string, value as String): return .string(value)
        case let (.date, value as Date): return .date(value)
        case let (.data, value as Data): return .data(value)
        case let (.bool, value as NSNumber): return .bool(value.boolValue)
        case let (.int, value as NSNumber): return .int(value.int64Value)
        case let (.double, value as NSNumber): return .double(value.doubleValue)
        default: return .null
        }
    }
}

/// A model's syncable fields, keyed by CloudKit field name.
public typealias SyncFields = [String: SyncValue]

public enum SyncError: Error, Equatable, Sendable, LogSafe {
    /// A college-class record reached the sync layer. It is refused (BD-02, B-4).
    case collegeRecordRefused
    case unknownRecordType
    case storeFailed
    case stateFailed

    public var logDescription: String {
        switch self {
        case .collegeRecordRefused: "collegeRecordRefused"
        case .unknownRecordType: "unknownRecordType"
        case .storeFailed: "storeFailed"
        case .stateFailed: "stateFailed"
        }
    }
}
