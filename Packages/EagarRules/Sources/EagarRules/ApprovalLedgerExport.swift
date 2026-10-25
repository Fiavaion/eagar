import Foundation

/// A content-free approval ledger export (Appendix F.6, FR-SEND-19).
///
/// There are deliberately no subject, body, address or name fields, and the schema limits
/// identifier fields to token characters.
public struct ApprovalLedgerExport: Sendable, Equatable, Codable {
    /// The value of the root `format` key.
    public static let format = "eagar-approval-ledger"
    /// The version this build writes.
    public static let currentFormatVersion = "1.0"

    public struct Period: Sendable, Equatable, Codable {
        /// `YYYY-MM-DD`.
        public var from: String
        /// `YYYY-MM-DD`.
        public var to: String

        public init(from: String, to: String) {
            self.from = from
            self.to = to
        }
    }

    public var formatVersion: String
    public var exportedAt: String
    public var period: Period
    public var events: [LedgerEvent]
    public var summary: LedgerSummary

    public init(
        formatVersion: String = ApprovalLedgerExport.currentFormatVersion, exportedAt: String,
        period: Period, events: [LedgerEvent], summary: LedgerSummary
    ) {
        self.formatVersion = formatVersion
        self.exportedAt = exportedAt
        self.period = period
        self.events = events
        self.summary = summary
    }

    private enum CodingKeys: String, CodingKey {
        case format, formatVersion, exportedAt, period, events, summary
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(String.self, forKey: .formatVersion)
        exportedAt = try container.decode(String.self, forKey: .exportedAt)
        period = try container.decode(Period.self, forKey: .period)
        events = try container.decode([LedgerEvent].self, forKey: .events)
        summary = try container.decode(LedgerSummary.self, forKey: .summary)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.format, forKey: .format)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(exportedAt, forKey: .exportedAt)
        try container.encode(period, forKey: .period)
        try container.encode(events, forKey: .events)
        try container.encode(summary, forKey: .summary)
    }
}

/// The guards of Appendix F, by name.
public enum GuardName: String, Sendable, Codable, CaseIterable, CodingKeyRepresentable {
    case wrongRecipient, missingAttachment, externalDomain, largeReplyAll, lateNight, personalData, tone, crossAccountLeak
}

/// One ledger entry.
public struct LedgerEvent: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case drafted, approved, edited, rejected, guardTriggered, held, released, undone, sent, dryRunSent, killSwitch
    }

    /// Where the draft came from (PRD §7.3 `Draft.origin`).
    public enum Origin: String, Sendable, Codable, CaseIterable {
        case manual, playbook, ai, followUp, delegation
    }

    /// Where the model that touched the draft ran (PRD §7.4 `DataLocality`, without the region).
    public enum ProviderLocality: String, Sendable, Codable, CaseIterable {
        case onDevice, macLocal, applePCC, selfHostedInstitutional, anthropicCloud
    }

    public var at: String
    public var lane: String?
    public var category: String?
    public var event: Kind
    public var origin: Origin?
    public var playbookVersion: Int?
    public var profileVersion: Int?
    public var providerLocality: ProviderLocality?
    public var editRatio: Double?
    public var editClasses: [String]?
    public var guardTriggers: [GuardName]?
    public var autonomyLevel: AutonomyLevel?
    public var dryRun: Bool?

    public init(
        at: String, lane: String? = nil, category: String? = nil, event: Kind, origin: Origin? = nil,
        playbookVersion: Int? = nil, profileVersion: Int? = nil, providerLocality: ProviderLocality? = nil,
        editRatio: Double? = nil, editClasses: [String]? = nil, guardTriggers: [GuardName]? = nil,
        autonomyLevel: AutonomyLevel? = nil, dryRun: Bool? = nil
    ) {
        self.at = at
        self.lane = lane
        self.category = category
        self.event = event
        self.origin = origin
        self.playbookVersion = playbookVersion
        self.profileVersion = profileVersion
        self.providerLocality = providerLocality
        self.editRatio = editRatio
        self.editClasses = editClasses
        self.guardTriggers = guardTriggers
        self.autonomyLevel = autonomyLevel
        self.dryRun = dryRun
    }
}

/// Totals for the export period.
public struct LedgerSummary: Sendable, Equatable, Codable {
    public var drafts: Int
    public var approved: Int
    public var rejected: Int
    public var medianEditRatio: Double
    public var guardCatches: [GuardName: Int]
    /// Must always be zero (BD-11); exported as measured so a breach would be visible.
    public var sendsWithoutApproval: Int

    public init(
        drafts: Int, approved: Int, rejected: Int, medianEditRatio: Double,
        guardCatches: [GuardName: Int], sendsWithoutApproval: Int
    ) {
        self.drafts = drafts
        self.approved = approved
        self.rejected = rejected
        self.medianEditRatio = medianEditRatio
        self.guardCatches = guardCatches
        self.sendsWithoutApproval = sendsWithoutApproval
    }
}
