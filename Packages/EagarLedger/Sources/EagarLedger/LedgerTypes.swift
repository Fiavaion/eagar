import EagarCore
import EagarStore
import Foundation

/// What a caller asks the ledger to record. The ledger decides the entry's class, store and
/// whether the payload may be kept.
public struct LedgerDraft: Sendable {
    public var kind: LedgerEventKind
    public var purpose: String
    public var payloadClasses: Set<DataClass>
    public var tier: Tier?
    /// Provider identifier, e.g. `anthropic`, `apple.onDevice`.
    public var destination: String?
    public var region: String?
    public var modelID: String?
    public var consentID: UUID?
    public var profileVersion: Int?
    /// The exact request bytes. Dropped by the ledger unless the call leaves Mark's devices
    /// and carries no college data (FR-PRIV-02, FR-PRIV-03).
    public var payload: Data?
    public var inputCount: Int
    /// A content-free note, e.g. a block reason. Only `LogSafe` values can be supplied.
    public private(set) var detail: String?

    public init(
        kind: LedgerEventKind,
        purpose: String,
        payloadClasses: Set<DataClass>,
        tier: Tier? = nil,
        destination: String? = nil,
        region: String? = nil,
        modelID: String? = nil,
        consentID: UUID? = nil,
        profileVersion: Int? = nil,
        payload: Data? = nil,
        inputCount: Int = 0,
        detail: (any LogSafe)? = nil
    ) {
        self.kind = kind
        self.purpose = purpose
        self.payloadClasses = payloadClasses
        self.tier = tier
        self.destination = destination
        self.region = region
        self.modelID = modelID
        self.consentID = consentID
        self.profileVersion = profileVersion
        self.payload = payload
        self.inputCount = inputCount
        self.detail = detail?.logDescription
    }
}

/// Filled in once, after the request finishes.
public struct LedgerCompletion: Sendable {
    public var outcome: LedgerOutcome
    public var inputTokens: Int?
    public var outputTokens: Int?
    public var cacheReadTokens: Int?
    public var cacheWriteTokens: Int?
    public var costMicroUSD: Int64?
    public var duration: Duration?

    public init(
        outcome: LedgerOutcome,
        inputTokens: Int? = nil,
        outputTokens: Int? = nil,
        cacheReadTokens: Int? = nil,
        cacheWriteTokens: Int? = nil,
        costMicroUSD: Int64? = nil,
        duration: Duration? = nil
    ) {
        self.outcome = outcome
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.costMicroUSD = costMicroUSD
        self.duration = duration
    }
}

/// A read-only, `Sendable` copy of a ledger entry, for the viewer and exports.
public struct LedgerRecord: Sendable, Codable, Identifiable, Equatable {
    public let id: UUID
    public let store: StoreKind
    public let at: Date
    public let kind: LedgerEventKind
    public let dataClass: DataClass
    public let payloadClasses: [DataClass]
    public let tier: Tier?
    public let destination: String?
    public let region: String?
    public let modelID: String?
    public let purpose: String
    public let consentID: UUID?
    public let profileVersion: Int?
    /// The exact payload as UTF-8 text, when one was kept.
    public internal(set) var payload: String?
    public let inputCount: Int
    public let detail: String?
    public let inputTokens: Int?
    public let outputTokens: Int?
    public let cacheReadTokens: Int?
    public let cacheWriteTokens: Int?
    public let costMicroUSD: Int64?
    public let durationMilliseconds: Int?
    public let outcome: LedgerOutcome

    init(_ entry: LedgerEntry, store: StoreKind) {
        id = entry.entryUUID
        self.store = store
        at = entry.at
        kind = LedgerEventKind(rawValue: entry.kindRaw) ?? .modelCall
        dataClass = entry.dataClass
        payloadClasses = entry.payloadClassesRaw.split(separator: ",").map { DataClass(rawValue: String($0)) ?? .college }
        tier = entry.tierRaw.flatMap(Tier.init(rawValue:))
        destination = entry.destination
        region = entry.region
        modelID = entry.modelID
        purpose = entry.purpose
        consentID = entry.consentUUID
        profileVersion = entry.profileVersion
        payload = entry.payload.map { String(decoding: $0, as: UTF8.self) }
        inputCount = entry.inputCount
        detail = entry.detail
        inputTokens = entry.inputTokens
        outputTokens = entry.outputTokens
        cacheReadTokens = entry.cacheReadTokens
        cacheWriteTokens = entry.cacheWriteTokens
        costMicroUSD = entry.costMicroUSD
        durationMilliseconds = entry.durationMilliseconds
        outcome = entry.outcome
    }

    /// A model call that reached Claude or Apple PCC with college data in it. Must always be zero (SM3).
    public var isCloudCallWithCollegeContent: Bool {
        guard kind == .modelCall || kind == .keyTest, outcome != .blocked else { return false }
        guard tier == .anthropicCloud || tier == .applePCC else { return false }
        return payloadClasses.contains(.college)
    }
}

/// The viewer's header line (FR-PRIV-05).
public struct LedgerSummary: Sendable, Equatable {
    public let cloudCallsWithCollegeContent: Int
    public let blockedAttempts: Int
    public let offDeviceCalls: Int
    public let totalCostMicroUSD: Int64
}

public enum LedgerError: Error, Equatable, Sendable, LogSafe {
    /// The entry could not be persisted. Callers must not send the request (FR-PRIV-01).
    case writeFailed
    case notFound
    case alreadyCompleted
    case readFailed
    case authenticationFailed
    case exportFailed

    public var logDescription: String {
        switch self {
        case .writeFailed: "writeFailed"
        case .notFound: "notFound"
        case .alreadyCompleted: "alreadyCompleted"
        case .readFailed: "readFailed"
        case .authenticationFailed: "authenticationFailed"
        case .exportFailed: "exportFailed"
        }
    }
}

/// The write side of the ledger, as the AI router sees it.
public protocol PrivacyLedgerWriting: Sendable {
    /// Persists a new entry and returns its ID. Throws ``LedgerError/writeFailed`` if it could
    /// not be saved; the caller must then not send anything.
    func record(_ draft: LedgerDraft) async throws(LedgerError) -> LedgerEntryID
    /// Fills in the outcome of a pending entry, once.
    func complete(_ id: LedgerEntryID, with completion: LedgerCompletion) async throws(LedgerError)
}
