import CloudKit
import EagarCore
import Foundation

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

    /// Reads a CloudKit value, using `hint` (the local field's current kind) to recover bools.
    static func from(_ value: Any?, hint: SyncValue?) -> SyncValue {
        switch value {
        case nil: return .null
        case let value as String: return .string(value)
        case let value as Date: return .date(value)
        case let value as Data: return .data(value)
        case let value as [String]: return .strings(value)
        case let value as [Int64]: return .ints(value)
        case let value as NSNumber:
            if case .bool = hint { return .bool(value.boolValue) }
            if case .double = hint { return .double(value.doubleValue) }
            if CFNumberIsFloatType(value) { return .double(value.doubleValue) }
            return .int(value.int64Value)
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
