import EagarCore
import EagarSecurity
import Foundation

/// Claude via Eagar's own `/v1/messages` client, with Mark's key (BD-07).
///
/// The request body is produced by ``encodeRequest(_:model:)`` before dispatch so the router
/// can ledger it; ``complete(_:)`` then sends exactly those bytes.
public struct AnthropicProvider: LLMProvider {
    public static let apiVersion = "2026-10-21"
    public static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    public let id = ProviderID("anthropic")
    private let secrets: any SecretStore
    private let session: URLSession
    private let region: String
    private let retryDelays: [Duration]
    private let log = EagarLog(.ai)

    /// - Parameters:
    ///   - region: `inference_geo` is left at its default; this only labels the locality (BD-07).
    ///   - retryDelays: back-off before each retry of a 429, 5xx or network failure (NFR-REL-01).
    public init(
        secrets: any SecretStore,
        session: URLSession = .shared,
        region: String = "global",
        retryDelays: [Duration] = [.seconds(1), .seconds(2)]
    ) {
        self.secrets = secrets
        self.session = session
        self.region = region
        self.retryDelays = retryDelays
    }

    public func capabilities() async -> ProviderCapabilities {
        ProviderCapabilities(
            locality: .anthropicCloud(region: region),
            defaultModel: ModelID("claude-haiku-5-5"),
            maxContextTokens: 1_000_000,
            supportsPromptCaching: true,
            supportsToolChoice: true,
            supportsStrictSchema: true,
            supportsBatch: false, // never used for personal or college content (FR-AI-11)
            supportsVision: true,
            supportsTokenCounting: true
        )
    }

    /// Reachable when a key is stored; network reachability shows up as a call failure.
    public func reachability() async -> Reachability {
        do {
            guard let key = try secrets.get(.anthropicAPIKey), !key.isEmpty else { return .unreachable }
            return .reachable
        } catch {
            log.error("Claude key unreadable: \(error)")
            return .unreachable
        }
    }

    public func encodeRequest(_ request: AIRequest, model: ModelID) throws(AIError) -> Data? {
        guard !request.inputs.isEmpty else { throw .provider(.misconfigured) }
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": request.maxOutputTokens,
            "messages": [[
                "role": "user",
                "content": request.inputs.map { ["type": "text", "text": $0.text] },
            ]],
        ]
        if let system = request.system {
            body["system"] = [["type": "text", "text": system.text, "cache_control": ["type": "ephemeral"]]]
        }
        var outputConfig: [String: Any] = [:]
        if let schema = request.outputSchema {
            guard let object = try? JSONSerialization.jsonObject(with: schema.json) else { throw .provider(.misconfigured) }
            outputConfig["format"] = ["type": "json_schema", "schema": object]
        }
        if let effort = request.effort {
            outputConfig["effort"] = effort.rawValue
        }
        if !outputConfig.isEmpty {
            body["output_config"] = outputConfig
        }
        do {
            return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys, .withoutEscapingSlashes])
        } catch {
            throw .provider(.misconfigured)
        }
    }

    public func complete(_ call: RoutedCall) async throws(AIError) -> LLMResponse {
        // Defence in depth behind the router: never send college data, never send unledgered bytes.
        guard call.tier == .anthropicCloud, call.effectiveClass != .college,
              call.ledgerEntryID != nil, let body = call.wirePayload
        else {
            log.fault("refused a routed call that violates the Claude preconditions")
            throw .provider(.misconfigured)
        }
        let stored: Secret?
        do {
            stored = try secrets.get(.anthropicAPIKey)
        } catch let .keychain(status) {
            throw .provider(.keychain(status: status))
        } catch {
            throw .provider(.keychain(status: 0))
        }
        guard let key = stored, !key.isEmpty else { throw .provider(.missingAPIKey) }

        var urlRequest = URLRequest(url: Self.endpoint, timeoutInterval: 60)
        urlRequest.httpMethod = "POST"
        urlRequest.httpBody = body
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        urlRequest.setValue("Bearer \(key.reveal())", forHTTPHeaderField: "authorization")

        var attempt = 0
        while true {
            let failure: ProviderFailure
            var retryAfter: Duration?
            do {
                let (data, response) = try await session.data(for: urlRequest)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200 { return try Self.decode(data) }
                failure = .http(status: status)
                if let header = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "retry-after"), let seconds = Double(header) {
                    retryAfter = .seconds(min(seconds, 10))
                }
            } catch let error as URLError where error.code == .cancelled {
                throw .provider(.network)
            } catch let error as URLError where error.code == .timedOut {
                failure = .timedOut
            } catch let error as AIError {
                throw error
            } catch {
                failure = .network
            }
            guard Self.isRetryable(failure), attempt < retryDelays.count, !Task.isCancelled else {
                throw .provider(failure)
            }
            log.notice("Claude request failed (\(failure)); retry \(attempt + 1)")
            do {
                try await Task.sleep(for: retryAfter ?? retryDelays[attempt])
            } catch {
                throw .provider(.network) // cancelled while waiting to retry
            }
            attempt += 1
        }
    }

    static func isRetryable(_ failure: ProviderFailure) -> Bool {
        switch failure {
        case let .http(status): status == 429 || status >= 500
        case .network, .timedOut: true
        case .missingAPIKey, .keychain, .decoding, .unavailable, .misconfigured, .contextTooLarge: false
        }
    }

    private struct WireResponse: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        struct Usage: Decodable {
            let input_tokens: Int?
            let output_tokens: Int?
            let cache_read_input_tokens: Int?
            let cache_creation_input_tokens: Int?
        }

        let model: String
        let content: [Block]
        let stop_reason: String?
        let usage: Usage?
    }

    static func decode(_ data: Data) throws(AIError) -> LLMResponse {
        let wire: WireResponse
        do {
            wire = try JSONDecoder().decode(WireResponse.self, from: data)
        } catch {
            throw .provider(.decoding)
        }
        let text = wire.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        let stop: StopReason = switch wire.stop_reason {
        case "end_turn": .endTurn
        case "max_tokens": .maxTokens
        case "refusal": .refusal
        case "tool_use": .toolUse
        default: .other
        }
        let usage = wire.usage.map {
            LLMUsage(
                inputTokens: $0.input_tokens ?? 0,
                outputTokens: $0.output_tokens ?? 0,
                cacheReadTokens: $0.cache_read_input_tokens ?? 0,
                cacheWriteTokens: $0.cache_creation_input_tokens ?? 0
            )
        }
        return LLMResponse(text: text, model: ModelID(wire.model), usage: usage, stopReason: stop)
    }
}
