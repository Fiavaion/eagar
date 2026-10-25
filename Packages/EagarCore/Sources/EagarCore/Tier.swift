/// Where a model call is processed (PRD §7.4 `DataLocality`, without the region).
///
/// Lives in EagarCore because the ledger (layer 3) records it and the AI router (layer 4) routes on it.
public enum Tier: String, Codable, Sendable, CaseIterable, LogSafe {
    /// Apple `SystemLanguageModel` on this device.
    case onDevice
    /// Ollama/MLX on Mark's Mac, on loopback or via the hub link.
    case macLocal
    /// Apple Private Cloud Compute.
    case applePCC
    /// Meitheal / DGX Sparks over the tailnet (NCAD estate).
    case selfHostedInstitutional
    /// The Claude API.
    case anthropicCloud

    /// Whether a call on this tier leaves Mark's own devices. Such calls need a privacy-ledger
    /// entry with the exact payload written before the request (BD-19, invariant 5).
    public var leavesOwnerDevices: Bool {
        switch self {
        case .onDevice, .macLocal: false
        case .applePCC, .selfHostedInstitutional, .anthropicCloud: true
        }
    }

    public var logDescription: String { rawValue }
}
