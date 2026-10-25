import EagarCore
import Foundation
import FoundationModels

/// Apple's on-device `SystemLanguageModel` (BD-08).
///
/// M0 stub: it reports real availability so routing decisions are correct, but generation
/// arrives in M1 (FR-AI-06: fresh session per item, sized to the runtime `contextSize`).
public struct AppleOnDeviceProvider: LLMProvider {
    public let id = ProviderID("apple.onDevice")

    public init() {}

    public func capabilities() async -> ProviderCapabilities {
        ProviderCapabilities(
            locality: .onDevice,
            defaultModel: ModelID("apple.systemLanguageModel"),
            // Read at runtime in M1; 4,096 is the documented floor (TN3193), never assumed as a ceiling.
            maxContextTokens: 4_096
        )
    }

    public func reachability() async -> Reachability {
        if case .available = SystemLanguageModel.default.availability { .reachable } else { .unreachable }
    }

    public func encodeRequest(_ request: AIRequest, model: ModelID) throws(AIError) -> Data? {
        nil
    }

    public func complete(_ call: RoutedCall) async throws(AIError) -> LLMResponse {
        throw .provider(.unavailable)
    }
}
