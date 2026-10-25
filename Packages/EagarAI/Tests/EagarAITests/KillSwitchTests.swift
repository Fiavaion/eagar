import EagarAITestSupport
import EagarCore
import Foundation
import Testing
@testable import EagarAI

/// A provider that takes 10 seconds unless cancelled.
struct SlowProvider: LLMProvider {
    let id = ProviderID("slow")
    func capabilities() async -> ProviderCapabilities { ProviderCapabilities(locality: .onDevice, defaultModel: ModelID("slow"), maxContextTokens: 4096) }
    func reachability() async -> Reachability { .reachable }
    func encodeRequest(_ request: AIRequest, model: ModelID) throws(AIError) -> Data? { nil }
    func complete(_ call: RoutedCall) async throws(AIError) -> LLMResponse {
        do {
            try await Task.sleep(for: .seconds(10))
        } catch {
            throw .provider(.network)
        }
        return LLMResponse(text: "late", model: call.model)
    }
}

struct KillSwitchTests {
    private let request = AIRequest(purpose: .triage, inputs: [ClassifiedPayload("x", dataClass: .publicContent)])

    /// FR-CORE-07 / M1 acceptance: the kill switch stops AI within 1 second, and is ledgered.
    @Test func haltStopsInFlightCallsWithinOneSecond() async throws {
        let ledger = InMemoryLedger()
        let router = makeRouter([SlowProvider()], ledger: ledger)
        let request = self.request
        let call = Task { () -> Result<LLMResponse, AIError> in
            do throws(AIError) { return .success(try await router.run(request)) } catch { return .failure(error) }
        }
        try await Task.sleep(for: .milliseconds(100)) // let the call start
        let started = ContinuousClock.now
        await router.halt()
        let result = await call.value as Result<LLMResponse, AIError>
        #expect(ContinuousClock.now - started < .seconds(1))
        guard case .failure(.halted) = result else { Issue.record("expected .halted, got \(result)"); return }
        #expect(ledger.entries.contains { $0.draft.kind == .killSwitch && $0.draft.detail == "1" })
        #expect(ledger.entries.first { $0.draft.kind == .modelCall }?.completion?.outcome == .failed)
    }

    @Test func haltedRouterRefusesNewCallsUntilResumed() async throws {
        let provider = RecordingProvider(.onDevice)
        let router = makeRouter([provider])
        await router.halt()
        #expect(await router.isHalted)
        await #expect(throws: AIError.halted) { try await router.run(request) }
        #expect(provider.recordedCalls.isEmpty)
        await router.resume()
        _ = try await router.run(request)
        #expect(provider.recordedCalls.count == 1)
    }

    @Test func haltIsIdempotent() async {
        let ledger = InMemoryLedger()
        let router = makeRouter([RecordingProvider(.onDevice)], ledger: ledger)
        await router.halt()
        await router.halt()
        #expect(ledger.entries.filter { $0.draft.kind == .killSwitch }.count == 1)
    }

    @Test func persistedStateRoundTrips() {
        let suite = "eagar.killswitch.\(UUID().uuidString)"
        let state = KillSwitchState(suiteName: suite)
        #expect(!state.isEngaged)
        state.set(engaged: true)
        #expect(KillSwitchState(suiteName: suite).isEngaged)
        state.set(engaged: false)
        #expect(!state.isEngaged)
    }
}
