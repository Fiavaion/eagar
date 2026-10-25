import EagarAI
import EagarCore
import EagarLedger
import Foundation
import Synchronization

/// A provider that records every call it receives and returns a canned response (PRD §7.4).
/// Boundary tests register one per tier and assert which ones were called.
public final class RecordingProvider: LLMProvider {
    public struct Call: Sendable {
        public let effectiveClass: DataClass
        public let tier: Tier
        public let model: ModelID
        public let ledgerEntryID: LedgerEntryID?
        public let wirePayload: Data?
        public let payloads: [ClassifiedPayload]
    }

    public let id: ProviderID
    public let locality: DataLocality
    private let reachable: Bool
    private let failure: AIError?
    private let calls = Mutex<[Call]>([])
    /// Runs inside `complete`, before the canned response, e.g. to assert the ledger state.
    private let onCall: (@Sendable (RoutedCall) async -> Void)?

    public init(
        _ locality: DataLocality,
        id: ProviderID? = nil,
        reachable: Bool = true,
        failure: AIError? = nil,
        onCall: (@Sendable (RoutedCall) async -> Void)? = nil
    ) {
        self.locality = locality
        self.id = id ?? ProviderID("recording.\(locality.tier.rawValue)")
        self.reachable = reachable
        self.failure = failure
        self.onCall = onCall
    }

    /// One reachable recording provider per tier.
    public static func oneOfEach() -> [RecordingProvider] {
        [.onDevice, .macLocal, .applePCC, .selfHostedInstitutional, .anthropicCloud(region: "global")].map { RecordingProvider($0) }
    }

    public var recordedCalls: [Call] { calls.withLock { $0 } }

    public func capabilities() async -> ProviderCapabilities {
        ProviderCapabilities(locality: locality, defaultModel: ModelID("claude-haiku-5-5"), maxContextTokens: 100_000)
    }

    public func reachability() async -> Reachability { reachable ? .reachable : .unreachable }

    public func encodeRequest(_ request: AIRequest, model: ModelID) throws(AIError) -> Data? {
        guard locality.tier.leavesOwnerDevices else { return nil }
        let lines = [model.rawValue] + request.allPayloads.map(\.text)
        return Data(lines.joined(separator: "\n").utf8)
    }

    public func complete(_ call: RoutedCall) async throws(AIError) -> LLMResponse {
        calls.withLock {
            $0.append(Call(
                effectiveClass: call.effectiveClass, tier: call.tier, model: call.model,
                ledgerEntryID: call.ledgerEntryID, wirePayload: call.wirePayload, payloads: call.request.allPayloads
            ))
        }
        await onCall?(call)
        if let failure { throw failure }
        return LLMResponse(text: "ok", model: call.model, usage: LLMUsage(inputTokens: 10, outputTokens: 2))
    }
}
