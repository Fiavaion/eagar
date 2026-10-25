import EagarCore
import EagarLedger
import Foundation

/// The single gateway to every model (BD-06, invariant 2).
///
/// For each request it computes the effective class with the taint rule, asks
/// ``PolicyEngine`` which tiers are permitted, picks a permitted reachable provider, writes the
/// ledger entry **before** dispatch (with the exact payload for off-device calls), then builds
/// the ``RoutedCall`` that providers require.
public actor AIRouter {
    /// Local tiers first: rules first, AI second, cloud last.
    static let tierPreference: [Tier] = [.onDevice, .macLocal, .selfHostedInstitutional, .applePCC, .anthropicCloud]

    private let providers: [any LLMProvider]
    private let ledger: any PrivacyLedgerWriting
    private let policy: any PolicySource
    private let catalog: ModelCatalog
    private let log = EagarLog(.ai)

    public init(providers: [any LLMProvider], ledger: any PrivacyLedgerWriting, policy: any PolicySource, catalog: ModelCatalog) {
        self.providers = providers
        self.ledger = ledger
        self.policy = policy
        self.catalog = catalog
    }

    public func run(_ request: AIRequest) async throws(AIError) -> LLMResponse {
        let payloads = request.allPayloads
        let effectiveClass = Taint.derive(.aiRequestPayload, from: payloads.map(\.dataClass))

        let snapshot: PolicySnapshot
        do {
            snapshot = try await policy.snapshot()
        } catch {
            log.error("policy unavailable; refusing \(request.purpose)")
            throw .noPermittedProvider
        }
        let inputs = payloads.map { snapshot.policyInput(for: $0, purpose: request.purpose) }
        let allowed = PolicyEngine.allowedTiers(for: inputs, settings: snapshot.settings, cloudPaused: snapshot.cloudPaused)

        if let requested = request.preferredTier, !allowed.contains(requested) {
            let reason = PolicyEngine.blockReason(
                for: requested, inputs: inputs, settings: snapshot.settings, cloudPaused: snapshot.cloudPaused
            ) ?? .tierDisabled
            try await recordBlocked(request, payloads: payloads, tier: requested, reason: reason)
            throw .boundaryViolation(requested: requested, reason: reason)
        }

        let candidates = request.requiresPreferredTier ? allowed.intersection(request.preferredTier.map { [$0] } ?? []) : allowed
        guard let (provider, capabilities) = await choose(from: candidates, preferred: request.preferredTier) else {
            log.notice("no permitted provider for \(request.purpose) (\(effectiveClass), \(allowed.count) tiers allowed)")
            throw .noPermittedProvider
        }
        let tier = capabilities.locality.tier
        let model = try resolveModel(request, tier: tier, capabilities: capabilities)

        let wirePayload = try provider.encodeRequest(request, model: model)
        if tier.leavesOwnerDevices, wirePayload == nil {
            // An off-device provider must ledger its exact bytes; one that cannot is unusable.
            throw .provider(.misconfigured)
        }

        let entryID: LedgerEntryID
        do {
            entryID = try await ledger.record(LedgerDraft(
                kind: request.purpose == .keyTest ? .keyTest : .modelCall,
                purpose: request.purpose.rawValue,
                payloadClasses: Set(payloads.map(\.dataClass)),
                tier: tier,
                destination: provider.id.rawValue,
                region: capabilities.locality.region,
                modelID: model.rawValue,
                consentID: consentUsed(payloads, purpose: request.purpose, tier: tier, snapshot: snapshot),
                payload: wirePayload,
                inputCount: payloads.count
            ))
        } catch {
            log.fault("ledger write failed; not sending \(request.purpose)")
            throw .ledgerWriteFailed
        }

        let call = RoutedCall(
            request: request, effectiveClass: effectiveClass, ledgerEntryID: entryID,
            model: model, tier: tier, wirePayload: wirePayload
        )
        let started = ContinuousClock.now
        do {
            var response = try await provider.complete(call)
            let cost = response.usage.flatMap { tier == .anthropicCloud ? catalog.costMicroUSD(model: response.model, usage: $0) : nil }
            await complete(entryID, LedgerCompletion(
                outcome: .succeeded,
                inputTokens: response.usage?.inputTokens,
                outputTokens: response.usage?.outputTokens,
                cacheReadTokens: response.usage?.cacheReadTokens,
                cacheWriteTokens: response.usage?.cacheWriteTokens,
                costMicroUSD: cost,
                duration: ContinuousClock.now - started
            ))
            response.tier = tier
            response.providerID = provider.id
            response.ledgerEntryID = entryID
            response.costMicroUSD = cost
            return response
        } catch {
            await complete(entryID, LedgerCompletion(outcome: .failed, duration: ContinuousClock.now - started))
            log.error("\(provider.id) failed: \(error)")
            throw error
        }
    }

    // MARK: - Steps

    private func choose(from allowed: Set<Tier>, preferred: Tier?) async -> (any LLMProvider, ProviderCapabilities)? {
        let order = (preferred.map { [$0] } ?? []) + Self.tierPreference.filter { $0 != preferred }
        for tier in order where allowed.contains(tier) {
            for provider in providers {
                let capabilities = await provider.capabilities()
                guard capabilities.locality.tier == tier, await provider.reachability() == .reachable else { continue }
                return (provider, capabilities)
            }
        }
        return nil
    }

    private func resolveModel(_ request: AIRequest, tier: Tier, capabilities: ProviderCapabilities) throws(AIError) -> ModelID {
        guard tier == .anthropicCloud else { return request.model ?? capabilities.defaultModel }
        guard let model = request.model ?? catalog.defaultModel(for: request.purpose) ?? Optional(capabilities.defaultModel),
              catalog.model(model)?.offered == true
        else { throw .modelNotOffered }
        return model
    }

    /// The consent record that authorised a personal payload on this tier, for the ledger.
    private func consentUsed(_ payloads: [ClassifiedPayload], purpose: AIPurpose, tier: Tier, snapshot: PolicySnapshot) -> UUID? {
        payloads.lazy
            .filter { $0.dataClass == .personal }
            .compactMap { snapshot.consents[ConsentKey(sourceID: $0.sourceID, purpose: purpose, tier: tier)] }
            .first
    }

    private func recordBlocked(_ request: AIRequest, payloads: [ClassifiedPayload], tier: Tier, reason: BlockReason) async throws(AIError) {
        log.notice("blocked \(request.purpose) to \(tier): \(reason)")
        do {
            _ = try await ledger.record(LedgerDraft(
                kind: .blocked,
                purpose: request.purpose.rawValue,
                payloadClasses: Set(payloads.map(\.dataClass)),
                tier: tier,
                inputCount: payloads.count,
                detail: reason
            ))
        } catch {
            throw .ledgerWriteFailed
        }
    }

    /// A completion that fails to save leaves the entry visibly `pending`; the call itself has
    /// already happened, so the response is still returned.
    private func complete(_ id: LedgerEntryID, _ completion: LedgerCompletion) async {
        do {
            try await ledger.complete(id, with: completion)
        } catch {
            log.fault("ledger completion failed for \(id): \(error)")
        }
    }
}
