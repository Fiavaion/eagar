import EagarCore

/// Global policy switches. Defaults are the PRD defaults; each one widens the policy only
/// when Mark changes it.
public struct PolicySettings: Sendable, Equatable {
    /// Whether Meitheal / the DGX Sparks count as Mark's local devices for college data (Q11).
    public var meithealIsLocal: Bool
    /// Whether personal data may go to Meitheal at all (Q11, §13 I2).
    public var meithealPersonalEnabled: Bool
    /// Whether raw personal bodies may use Apple PCC (§7.4 "✅ if enabled").
    public var applePCCForRawPersonal: Bool

    public init(meithealIsLocal: Bool = false, meithealPersonalEnabled: Bool = false, applePCCForRawPersonal: Bool = false) {
        self.meithealIsLocal = meithealIsLocal
        self.meithealPersonalEnabled = meithealPersonalEnabled
        self.applePCCForRawPersonal = applePCCForRawPersonal
    }
}

/// Everything the policy needs to know about one input.
public struct PolicyInput: Sendable, Equatable {
    public var dataClass: DataClass
    public var kind: ContentKind
    public var mode: ProcessingMode
    /// Tiers for which an active consent covers this input's source and the request's purpose.
    public var consentedTiers: Set<Tier>

    public init(dataClass: DataClass, kind: ContentKind, mode: ProcessingMode, consentedTiers: Set<Tier> = []) {
        self.dataClass = dataClass
        self.kind = kind
        self.mode = mode
        self.consentedTiers = consentedTiers
    }
}

/// The routing policy (PRD §7.4 policy table, BD-04, BD-05). Pure and exhaustively tested.
public enum PolicyEngine {
    /// Tiers permitted for a single input.
    public static func allowedTiers(for input: PolicyInput, settings: PolicySettings) -> Set<Tier> {
        byClass(input, settings).intersection(ceiling(of: input.mode, settings))
    }

    /// Tiers permitted for a whole request: the intersection over every input, so each input's
    /// restrictions hold. Cloud tiers are removed while cloud features are paused.
    public static func allowedTiers(for inputs: [PolicyInput], settings: PolicySettings, cloudPaused: Bool = false) -> Set<Tier> {
        var allowed = inputs.reduce(Set(Tier.allCases)) { $0.intersection(allowedTiers(for: $1, settings: settings)) }
        if cloudPaused { allowed.remove(.anthropicCloud) }
        return allowed
    }

    /// Why `tier` is not permitted, most fundamental reason first. `nil` if it is permitted.
    public static func blockReason(for tier: Tier, inputs: [PolicyInput], settings: PolicySettings, cloudPaused: Bool = false) -> BlockReason? {
        guard !allowedTiers(for: inputs, settings: settings, cloudPaused: cloudPaused).contains(tier) else { return nil }
        if inputs.contains(where: { $0.mode == .rulesOnly }) { return .rulesOnlySource }
        if inputs.contains(where: { $0.dataClass == .college }) { return .collegeBoundary }
        if cloudPaused && tier == .anthropicCloud { return .cloudPaused }
        let withConsent = inputs.map { input in
            var granted = input
            granted.consentedTiers.insert(tier)
            return granted
        }
        if allowedTiers(for: withConsent, settings: settings).contains(tier) { return .consentRequired }
        return .tierDisabled
    }

    /// The most a processing mode allows (BD-05).
    static func ceiling(of mode: ProcessingMode, _ settings: PolicySettings) -> Set<Tier> {
        switch mode {
        case .rulesOnly:
            []
        case .localAI:
            settings.meithealIsLocal ? [.onDevice, .macLocal, .selfHostedInstitutional] : [.onDevice, .macLocal]
        case .cloudAllowed:
            Set(Tier.allCases)
        }
    }

    /// The §7.4 table rows.
    static func byClass(_ input: PolicyInput, _ settings: PolicySettings) -> Set<Tier> {
        var tiers: Set<Tier> = [.onDevice, .macLocal]
        switch input.dataClass {
        case .college:
            if settings.meithealIsLocal { tiers.insert(.selfHostedInstitutional) }
        case .personal:
            switch input.kind {
            case .rawBody:
                if settings.applePCCForRawPersonal { tiers.insert(.applePCC) }
            case .derivedItem:
                tiers.insert(.applePCC)
            }
            if settings.meithealPersonalEnabled { tiers.insert(.selfHostedInstitutional) }
            if input.consentedTiers.contains(.anthropicCloud) { tiers.insert(.anthropicCloud) }
        case .approvedProfile, .publicContent:
            tiers = Set(Tier.allCases)
        }
        return tiers
    }
}
