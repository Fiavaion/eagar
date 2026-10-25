import EagarCore
import EagarStore
import Foundation
import SwiftData

/// Identifies a ledger entry and the store it lives in.
public struct LedgerEntryID: Hashable, Codable, Sendable, LogSafe {
    public let rawValue: UUID
    public let store: StoreKind

    public init(rawValue: UUID, store: StoreKind) {
        self.rawValue = rawValue
        self.store = store
    }

    public var logDescription: String { rawValue.uuidString }
}

/// What a ledger entry records (FR-PRIV-04).
public enum LedgerEventKind: String, Codable, Sendable, CaseIterable, LogSafe {
    /// A model call, on or off device.
    case modelCall
    /// A model call the router refused.
    case blocked
    /// The BYOK "test key" call.
    case keyTest
    /// Learning-pipeline purge (M4).
    case purge
    /// MCP tool call (M6).
    case mcpCall
    /// Push-server registration (M5).
    case pushRegistration
    /// Kill switch used (M1).
    case killSwitch
    /// Ledger entries erased by the owner.
    case erase

    public var logDescription: String { rawValue }
}

public enum LedgerOutcome: String, Codable, Sendable, CaseIterable, LogSafe {
    /// Written before the request; not yet completed.
    case pending
    case succeeded
    case failed
    case blocked
    /// Recorded for completeness; nothing was sent (e.g. erase, purge).
    case notApplicable

    public var logDescription: String { rawValue }
}

/// One privacy-ledger row (BD-19, FR-PRIV-02). Append-only: rows are created by
/// ``PrivacyLedger`` and only a pending row's completion fields are ever filled in once.
///
/// CloudKit-compatible: every attribute optional or defaulted, no unique constraints.
@Model
public final class LedgerEntry: Classified {
    var entryUUID: UUID = UUID()
    var at: Date = Date.distantPast
    var kindRaw: String = LedgerEventKind.modelCall.rawValue
    var dataClassRaw: String = DataClass.college.rawValue
    /// Comma-separated `DataClass` raw values of the inputs.
    var payloadClassesRaw: String = ""
    var tierRaw: String?
    var destination: String?
    var region: String?
    var modelID: String?
    var purpose: String = ""
    var consentUUID: UUID?
    var profileVersion: Int?
    /// The exact bytes sent off-device. Never set for college-class or on-device entries.
    @Attribute(.externalStorage) var payload: Data?
    var inputCount: Int = 0
    var detail: String?
    var inputTokens: Int?
    var outputTokens: Int?
    var cacheReadTokens: Int?
    var cacheWriteTokens: Int?
    var costMicroUSD: Int64?
    var durationMilliseconds: Int?
    var outcomeRaw: String = LedgerOutcome.pending.rawValue

    init(id: UUID, at: Date, dataClass: DataClass, draft: LedgerDraft, payload: Data?, outcome: LedgerOutcome) {
        entryUUID = id
        self.at = at
        kindRaw = draft.kind.rawValue
        dataClassRaw = dataClass.rawValue
        payloadClassesRaw = draft.payloadClasses.sorted().map(\.rawValue).joined(separator: ",")
        tierRaw = draft.tier?.rawValue
        destination = draft.destination
        region = draft.region
        modelID = draft.modelID
        purpose = draft.purpose
        consentUUID = draft.consentID
        profileVersion = draft.profileVersion
        self.payload = payload
        inputCount = draft.inputCount
        detail = draft.detail
        outcomeRaw = outcome.rawValue
    }

    /// Unknown raw values read as `college`, the most restrictive class.
    public var dataClass: DataClass { DataClass(rawValue: dataClassRaw) ?? .college }
    public var sourceID: SourceID? { nil }

    var outcome: LedgerOutcome { LedgerOutcome(rawValue: outcomeRaw) ?? .failed }
}
