import EagarCore
import Foundation

/// The policy state the router reads, fresh, for every request.
public struct PolicySnapshot: Sendable {
    public var settings: PolicySettings
    /// Processing mode per registered source. A source missing from this map is treated as
    /// `rulesOnly` (fail closed).
    public var sourceModes: [SourceID: ProcessingMode]
    /// Active consents and their record IDs.
    public var consents: [ConsentKey: UUID]
    /// Cloud features are paused, e.g. the monthly spend cap is reached (FR-AI-09).
    public var cloudPaused: Bool

    public init(
        settings: PolicySettings = PolicySettings(),
        sourceModes: [SourceID: ProcessingMode] = [:],
        consents: [ConsentKey: UUID] = [:],
        cloudPaused: Bool = false
    ) {
        self.settings = settings
        self.sourceModes = sourceModes
        self.consents = consents
        self.cloudPaused = cloudPaused
    }

    /// The processing mode for a payload's source. User-authored content (no source) is
    /// bounded by its class alone.
    public func mode(for sourceID: SourceID?) -> ProcessingMode {
        guard let sourceID else { return .cloudAllowed }
        return sourceModes[sourceID] ?? .rulesOnly
    }

    /// Policy facts for one payload of a request with `purpose`.
    func policyInput(for payload: ClassifiedPayload, purpose: AIPurpose) -> PolicyInput {
        let consented = Set(Tier.allCases.filter {
            consents[ConsentKey(sourceID: payload.sourceID, purpose: purpose, tier: $0)] != nil
        })
        return PolicyInput(dataClass: payload.dataClass, kind: payload.kind, mode: mode(for: payload.sourceID), consentedTiers: consented)
    }
}

/// Supplies the current policy. The app builds it from settings, sources, consents and the spend meter.
public protocol PolicySource: Sendable {
    func snapshot() async throws -> PolicySnapshot
}

/// A fixed snapshot, for tests and previews.
public struct StaticPolicySource: PolicySource {
    public let value: PolicySnapshot
    public init(_ value: PolicySnapshot) { self.value = value }
    public func snapshot() async throws -> PolicySnapshot { value }
}
