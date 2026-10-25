import EagarCore
import EagarLedger
import Foundation

/// The capability token for a model call (BD-06).
///
/// Its initialiser has `package` access, so only code inside the EagarAI package (the router)
/// can create one. Feature code therefore cannot call a provider without going through
/// ``AIRouter``, which checks policy and writes the ledger first.
public struct RoutedCall: Sendable {
    public let request: AIRequest
    public let effectiveClass: DataClass
    /// Set for every call; off-device providers refuse a call without one.
    public let ledgerEntryID: LedgerEntryID?
    public let model: ModelID
    public let tier: Tier
    /// The exact bytes recorded in the ledger. Wire providers send these verbatim.
    public let wirePayload: Data?

    package init(
        request: AIRequest,
        effectiveClass: DataClass,
        ledgerEntryID: LedgerEntryID?,
        model: ModelID,
        tier: Tier,
        wirePayload: Data?
    ) {
        self.request = request
        self.effectiveClass = effectiveClass
        self.ledgerEntryID = ledgerEntryID
        self.model = model
        self.tier = tier
        self.wirePayload = wirePayload
    }
}

/// A model backend. Providers accept only ``RoutedCall``.
public protocol LLMProvider: Sendable {
    var id: ProviderID { get }
    func capabilities() async -> ProviderCapabilities
    func reachability() async -> Reachability
    /// The exact request body `complete` will send, so the router can ledger it first.
    /// Pure: no I/O. Returns `nil` for providers with no wire format (on-device models).
    func encodeRequest(_ request: AIRequest, model: ModelID) throws(AIError) -> Data?
    func complete(_ call: RoutedCall) async throws(AIError) -> LLMResponse
    func stream(_ call: RoutedCall) -> AsyncThrowingStream<LLMEvent, Error>
}

extension LLMProvider {
    /// Default: one completed event from `complete`. Streaming providers override (M1).
    public func stream(_ call: RoutedCall) -> AsyncThrowingStream<LLMEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    continuation.yield(.completed(try await complete(call)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
