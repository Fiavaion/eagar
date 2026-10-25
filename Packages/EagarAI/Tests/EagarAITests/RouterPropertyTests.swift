import EagarAITestSupport
import EagarCore
import Foundation
import Testing
@testable import EagarAI

/// Deterministic SplitMix64, so failures reproduce from the printed seed.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

struct RouterPropertyTests {
    /// B-5: 10,000 random requests (random class mixes, kinds, source modes, consents, settings,
    /// preferred tiers and reachability) never produce a disallowed dispatch.
    @Test func Boundary_B5_randomRequestsNeverDispatchDisallowed() async throws {
        let iterations = 10_000
        var rng = SeededGenerator(seed: 0xEA6A_0B5)
        var dispatched = 0
        var refused = 0

        for iteration in 0..<iterations {
            let settings = PolicySettings(
                meithealIsLocal: Bool.random(using: &rng),
                meithealPersonalEnabled: Bool.random(using: &rng),
                applePCCForRawPersonal: Bool.random(using: &rng)
            )
            let sources = (0..<3).map { _ in SourceID(UUID()) }
            var modes: [SourceID: ProcessingMode] = [:]
            for source in sources where Int.random(in: 0..<5, using: &rng) > 0 { // some sources unregistered
                modes[source] = ProcessingMode.allCases.randomElement(using: &rng)!
            }
            let purpose = AIPurpose.allCases.randomElement(using: &rng)!
            var consents: [ConsentKey: UUID] = [:]
            for source in sources where Bool.random(using: &rng) {
                consents[ConsentKey(sourceID: source, purpose: purpose, tier: .anthropicCloud)] = UUID()
            }
            if Bool.random(using: &rng) { consents[ConsentKey(sourceID: nil, purpose: purpose, tier: .anthropicCloud)] = UUID() }

            let payloads = (0..<Int.random(in: 1...5, using: &rng)).map { _ in
                ClassifiedPayload(
                    "item",
                    dataClass: DataClass.allCases.randomElement(using: &rng)!,
                    sourceID: Bool.random(using: &rng) ? sources.randomElement(using: &rng)! : nil,
                    kind: ContentKind.allCases.randomElement(using: &rng)!
                )
            }
            let hasSystem = Int.random(in: 0..<4, using: &rng) == 0
            let request = AIRequest(
                purpose: purpose,
                inputs: hasSystem ? Array(payloads.dropLast()) : payloads,
                system: hasSystem ? payloads.last : nil,
                preferredTier: Bool.random(using: &rng) ? Tier.allCases.randomElement(using: &rng)! : nil
            )
            guard !request.inputs.isEmpty || request.system != nil else { continue }

            let providers = [DataLocality.onDevice, .macLocal, .applePCC, .selfHostedInstitutional, .anthropicCloud(region: "global")]
                .map { RecordingProvider($0, reachable: Int.random(in: 0..<4, using: &rng) > 0) }
            let snapshot = PolicySnapshot(settings: settings, sourceModes: modes, consents: consents, cloudPaused: Int.random(in: 0..<10, using: &rng) == 0)
            let router = makeRouter(providers, policy: snapshot)

            do {
                _ = try await router.run(request)
                dispatched += 1
            } catch {
                refused += 1
            }

            let calls = providers.flatMap(\.recordedCalls)
            #expect(calls.count <= 1)
            for call in calls {
                for payload in request.allPayloads {
                    let input = PolicyInput(
                        dataClass: payload.dataClass,
                        kind: payload.kind,
                        mode: snapshot.mode(for: payload.sourceID),
                        consentedTiers: consents[ConsentKey(sourceID: payload.sourceID, purpose: purpose, tier: .anthropicCloud)] == nil ? [] : [.anthropicCloud]
                    )
                    #expect(PolicyOracle.permits(call.tier, input, settings), "iteration \(iteration): \(payload.dataClass) to \(call.tier)")
                }
                // The invariants, stated directly.
                if call.effectiveClass == .college {
                    #expect(call.tier != .anthropicCloud && call.tier != .applePCC)
                    #expect(call.tier != .selfHostedInstitutional || settings.meithealIsLocal)
                }
                #expect(!request.allPayloads.contains { snapshot.mode(for: $0.sourceID) == .rulesOnly })
                #expect(!(snapshot.cloudPaused && call.tier == .anthropicCloud))
                #expect(call.ledgerEntryID != nil)
            }
        }
        // The generator must exercise both outcomes meaningfully.
        #expect(dispatched > 1_000 && refused > 1_000, "dispatched \(dispatched), refused \(refused)")
    }
}
