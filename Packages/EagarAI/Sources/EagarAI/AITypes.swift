import EagarCore
import EagarLedger
import Foundation

/// Identifies a provider instance, e.g. `anthropic`, `apple.onDevice`.
public struct ProviderID: Hashable, Codable, Sendable, LogSafe {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var logDescription: String { rawValue }
}

/// A model identifier as the provider spells it, e.g. `claude-haiku-5-5`.
public struct ModelID: Hashable, Codable, Sendable, LogSafe {
    public let rawValue: String
    public init(_ rawValue: String) { self.rawValue = rawValue }
    public init(from decoder: any Decoder) throws { rawValue = try decoder.singleValueContainer().decode(String.self) }
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
    public var logDescription: String { rawValue }
}

/// Where a provider processes data (PRD §7.4).
public enum DataLocality: Hashable, Sendable {
    case onDevice
    case macLocal
    case applePCC
    case selfHostedInstitutional
    /// `"global"` or `"us"`.
    case anthropicCloud(region: String)

    public var tier: Tier {
        switch self {
        case .onDevice: .onDevice
        case .macLocal: .macLocal
        case .applePCC: .applePCC
        case .selfHostedInstitutional: .selfHostedInstitutional
        case .anthropicCloud: .anthropicCloud
        }
    }

    public var region: String? {
        if case let .anthropicCloud(region) = self { region } else { nil }
    }
}

/// Provider capability flags (PRD §7.4). Behaviour is driven by these, never by provider identity.
public struct ProviderCapabilities: Sendable {
    public var locality: DataLocality
    public var defaultModel: ModelID
    public var maxContextTokens: Int
    public var supportsPromptCaching: Bool
    public var supportsToolChoice: Bool
    public var supportsStrictSchema: Bool
    public var supportsBatch: Bool
    public var supportsVision: Bool
    public var supportsTokenCounting: Bool

    public init(
        locality: DataLocality,
        defaultModel: ModelID,
        maxContextTokens: Int,
        supportsPromptCaching: Bool = false,
        supportsToolChoice: Bool = false,
        supportsStrictSchema: Bool = false,
        supportsBatch: Bool = false,
        supportsVision: Bool = false,
        supportsTokenCounting: Bool = false
    ) {
        self.locality = locality
        self.defaultModel = defaultModel
        self.maxContextTokens = maxContextTokens
        self.supportsPromptCaching = supportsPromptCaching
        self.supportsToolChoice = supportsToolChoice
        self.supportsStrictSchema = supportsStrictSchema
        self.supportsBatch = supportsBatch
        self.supportsVision = supportsVision
        self.supportsTokenCounting = supportsTokenCounting
    }
}

public enum Reachability: Sendable, Equatable {
    case reachable
    case unreachable
}

/// Distinguishes raw content from minimised derived items, which the policy treats differently
/// for personal data (BD-05).
public enum ContentKind: String, Codable, Sendable, CaseIterable, LogSafe {
    /// A raw message body, transcript or document.
    case rawBody
    /// A minimised item derived from content (a deadline, a trial row, a summary line).
    case derivedItem

    public var logDescription: String { rawValue }
}

/// One piece of text bound for a model, with its class and origin. Every byte that reaches a
/// provider arrives as one of these, including the system prompt.
public struct ClassifiedPayload: Sendable, Classified {
    public var text: String
    public var dataClass: DataClass
    public var sourceID: SourceID?
    public var kind: ContentKind

    public init(_ text: String, dataClass: DataClass, sourceID: SourceID? = nil, kind: ContentKind = .derivedItem) {
        self.text = text
        self.dataClass = dataClass
        self.sourceID = sourceID
        self.kind = kind
    }
}

/// Why a model is being called. Consent is granted per purpose (BD-20).
public enum AIPurpose: String, Codable, Sendable, CaseIterable, LogSafe {
    case keyTest
    case triage
    case extraction
    case briefPhrase
    case weeklyReview
    case planning
    case draftReply
    case profileAnalysis

    /// Which default model class the purpose uses (FR-AI-08).
    public var modelClass: ModelClass {
        switch self {
        case .keyTest, .triage, .extraction: .light
        case .briefPhrase, .weeklyReview, .planning, .draftReply, .profileAnalysis: .standard
        }
    }

    public var logDescription: String { rawValue }
}

/// Default model classes in `models.json`.
public enum ModelClass: String, Codable, Sendable {
    case light, standard
}

/// Requested reasoning effort, mapped to `output_config.effort` where supported.
public enum Effort: String, Codable, Sendable {
    case low, medium, high
}

/// A JSON Schema for structured output. The same schema is used for Claude and for
/// client-side validation of local models (PRD §7.4).
public struct JSONSchema: Sendable, Equatable {
    public let name: String
    /// The schema document, UTF-8 JSON.
    public let json: Data

    public init(name: String, json: Data) {
        self.name = name
        self.json = json
    }
}

/// What feature code asks the router for.
public struct AIRequest: Sendable {
    public var purpose: AIPurpose
    public var inputs: [ClassifiedPayload]
    /// The system prompt is classified like any input and takes part in the taint rule.
    public var system: ClassifiedPayload?
    public var outputSchema: JSONSchema?
    /// Ask for a specific tier. If policy forbids it the router refuses and ledgers a blocked
    /// attempt rather than silently choosing another tier.
    public var preferredTier: Tier?
    /// Override the default model for the chosen provider (e.g. Mark selects Opus).
    public var model: ModelID?
    public var maxOutputTokens: Int
    public var effort: Effort?

    public init(
        purpose: AIPurpose,
        inputs: [ClassifiedPayload],
        system: ClassifiedPayload? = nil,
        outputSchema: JSONSchema? = nil,
        preferredTier: Tier? = nil,
        model: ModelID? = nil,
        maxOutputTokens: Int = 1024,
        effort: Effort? = nil
    ) {
        self.purpose = purpose
        self.inputs = inputs
        self.system = system
        self.outputSchema = outputSchema
        self.preferredTier = preferredTier
        self.model = model
        self.maxOutputTokens = maxOutputTokens
        self.effort = effort
    }

    /// Every classified piece of the request.
    public var allPayloads: [ClassifiedPayload] {
        inputs + (system.map { [$0] } ?? [])
    }
}

/// Token usage as reported by the provider.
public struct LLMUsage: Sendable, Equatable, Codable {
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var cacheWriteTokens: Int

    public init(inputTokens: Int = 0, outputTokens: Int = 0, cacheReadTokens: Int = 0, cacheWriteTokens: Int = 0) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
    }

    /// Total prompt size: uncached input plus cache reads and writes.
    public var promptTokens: Int { inputTokens + cacheReadTokens + cacheWriteTokens }
}

public enum StopReason: String, Sendable, Codable {
    case endTurn, maxTokens, refusal, toolUse, other
}

public struct LLMResponse: Sendable {
    public var text: String
    public var model: ModelID
    public var usage: LLMUsage?
    public var stopReason: StopReason
    /// Filled in by the router: where the call ran and its ledger entry (FR-AI-12).
    public var tier: Tier?
    public var providerID: ProviderID?
    public var ledgerEntryID: LedgerEntryID?
    public var costMicroUSD: Int64?

    public init(text: String, model: ModelID, usage: LLMUsage? = nil, stopReason: StopReason = .endTurn) {
        self.text = text
        self.model = model
        self.usage = usage
        self.stopReason = stopReason
    }
}

public enum LLMEvent: Sendable {
    case textDelta(String)
    case completed(LLMResponse)
}

/// Why the router refused a tier.
public enum BlockReason: String, Sendable, Codable, LogSafe {
    /// College data may not leave Mark's devices (OD-2).
    case collegeBoundary
    /// The source is rules-only; no model call of any kind (invariant 3).
    case rulesOnlySource
    /// No active consent for this source, feature and provider (BD-20).
    case consentRequired
    /// The tier is switched off in settings.
    case tierDisabled
    /// Cloud features are paused (spend cap reached).
    case cloudPaused

    public var logDescription: String { rawValue }
}

/// Provider failures, content-free.
public enum ProviderFailure: Sendable, Equatable, LogSafe {
    case missingAPIKey
    case http(status: Int)
    case network
    case timedOut
    case decoding
    case unavailable
    case misconfigured

    public var logDescription: String {
        switch self {
        case .missingAPIKey: "missingAPIKey"
        case let .http(status): "http(\(status))"
        case .network: "network"
        case .timedOut: "timedOut"
        case .decoding: "decoding"
        case .unavailable: "unavailable"
        case .misconfigured: "misconfigured"
        }
    }
}

public enum AIError: Error, Sendable, Equatable, LogSafe {
    /// An explicitly requested tier is not permitted for this payload (FR-AI-02). Ledgered as blocked.
    case boundaryViolation(requested: Tier, reason: BlockReason)
    /// No permitted, reachable provider. Callers fall back to rules (PRD §7.4 step 4).
    case noPermittedProvider
    /// The ledger entry could not be written, so nothing was sent (FR-PRIV-01).
    case ledgerWriteFailed
    /// The requested model is not in the catalogue or not offered.
    case modelNotOffered
    case provider(ProviderFailure)

    public var logDescription: String {
        switch self {
        case let .boundaryViolation(requested, reason): "boundaryViolation(\(requested.rawValue), \(reason.rawValue))"
        case .noPermittedProvider: "noPermittedProvider"
        case .ledgerWriteFailed: "ledgerWriteFailed"
        case .modelNotOffered: "modelNotOffered"
        case let .provider(failure): "provider(\(failure.logDescription))"
        }
    }
}
