import EagarCore
import Foundation

/// The BYOK "test key" check (FR-AI-07, BD-07): a minimal Claude call through the router, so
/// it is ledgered like any other call (kind `keyTest`, FR-PRIV-04).
public enum KeyTester {
    public enum Outcome: Sendable, Equatable {
        case valid(model: ModelID, costMicroUSD: Int64?)
        case invalidKey
        /// No key is stored on this device, so the Claude provider is not available.
        case noKey
        case failed(AIError)
    }

    /// The fixed prompt. Public content: it carries no data about anyone.
    static let prompt = "Reply with the single word OK."

    public static func run(using router: AIRouter, model: ModelID = ModelID("claude-haiku-5-5")) async -> Outcome {
        let request = AIRequest(
            purpose: .keyTest,
            inputs: [ClassifiedPayload(prompt, dataClass: .publicContent)],
            preferredTier: .anthropicCloud,
            model: model,
            maxOutputTokens: 64,
            effort: .low
        )
        do {
            let response = try await router.run(request)
            return .valid(model: response.model, costMicroUSD: response.costMicroUSD)
        } catch .provider(.http(status: 401)), .provider(.http(status: 403)) {
            return .invalidKey
        } catch .provider(.missingAPIKey), .noPermittedProvider {
            return .noKey
        } catch {
            return .failed(error)
        }
    }
}
