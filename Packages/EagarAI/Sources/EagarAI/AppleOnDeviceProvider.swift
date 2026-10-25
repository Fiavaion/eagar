import EagarCore
import Foundation
import FoundationModels

/// Apple's on-device `SystemLanguageModel` (BD-08, FR-AI-06).
///
/// Each call runs in a fresh `LanguageModelSession` (one item per session). The prompt must fit
/// the model's context, read at runtime: callers split larger work into separate requests.
public struct AppleOnDeviceProvider: LLMProvider {
    public let id = ProviderID("apple.onDevice")
    static let modelID = ModelID("apple.systemLanguageModel")
    /// Used only on OS versions that cannot report the context size (before 26.4): the
    /// documented floor (TN3193), never assumed as the ceiling.
    static let fallbackContextTokens = 4_096

    public init() {}

    public func capabilities() async -> ProviderCapabilities {
        ProviderCapabilities(locality: .onDevice, defaultModel: Self.modelID, maxContextTokens: await contextSize())
    }

    public func reachability() async -> Reachability {
        Self.isAvailable ? .reachable : .unreachable
    }

    /// Whether Apple Intelligence's on-device model can run here now.
    public static var isAvailable: Bool {
        if case .available = SystemLanguageModel.default.availability { true } else { false }
    }

    public func encodeRequest(_ request: AIRequest, model: ModelID) throws(AIError) -> Data? {
        nil
    }

    public func complete(_ call: RoutedCall) async throws(AIError) -> LLMResponse {
        guard call.tier == .onDevice else { throw .provider(.misconfigured) }
        // Structured output via @Generable arrives with the features that need it.
        guard call.request.outputSchema == nil else { throw .provider(.misconfigured) }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { throw .provider(.unavailable) }

        let prompt = Self.prompt(for: call.request)
        let instructions = call.request.system?.text
        let needed = await tokenEstimate(prompt: prompt, instructions: instructions)
        guard Self.fits(needed: needed, output: call.request.maxOutputTokens, context: await contextSize()) else {
            throw .provider(.contextTooLarge)
        }

        let session = LanguageModelSession(model: model, instructions: instructions)
        do {
            let response = try await session.respond(
                to: prompt,
                options: GenerationOptions(maximumResponseTokens: call.request.maxOutputTokens)
            )
            return LLMResponse(text: response.content, model: Self.modelID)
        } catch let error as LanguageModelSession.GenerationError {
            switch error {
            case .exceededContextWindowSize: throw .provider(.contextTooLarge)
            case .refusal, .guardrailViolation: return LLMResponse(text: "", model: Self.modelID, stopReason: .refusal)
            default: throw .provider(.unavailable)
            }
        } catch {
            throw .provider(.unavailable)
        }
    }

    // MARK: - Sizing

    /// The prompt for one item: the inputs, separated by blank lines.
    static func prompt(for request: AIRequest) -> String {
        request.inputs.map(\.text).joined(separator: "\n\n")
    }

    /// Whether the prompt plus the requested output fits the context.
    static func fits(needed: Int, output: Int, context: Int) -> Bool {
        needed + output <= context
    }

    /// A conservative estimate before 26.4: about 3 characters per token, rounded up.
    static func estimatedTokens(_ text: String) -> Int {
        (text.count + 2) / 3
    }

    private func contextSize() async -> Int {
        if #available(iOS 26.4, macOS 26.4, *) {
            return SystemLanguageModel.default.contextSize
        }
        return Self.fallbackContextTokens
    }

    private func tokenEstimate(prompt: String, instructions: String?) async -> Int {
        if #available(iOS 26.4, macOS 26.4, *) {
            let model = SystemLanguageModel.default
            do {
                var total = try await model.tokenCount(for: prompt)
                if let instructions {
                    total += try await model.tokenCount(for: Instructions(instructions))
                }
                return total
            } catch {
                EagarLog(.ai).notice("on-device token count unavailable; estimating")
            }
        }
        return Self.estimatedTokens(prompt) + Self.estimatedTokens(instructions ?? "")
    }
}
