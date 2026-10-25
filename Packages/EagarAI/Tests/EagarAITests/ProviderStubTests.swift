import EagarAITestSupport
import EagarCore
import Foundation
import Testing
@testable import EagarAI

struct ProviderStubTests {
    @Test func appleOnDeviceStubIsLocalAndHasNoWireFormat() async throws {
        let provider = AppleOnDeviceProvider()
        let capabilities = await provider.capabilities()
        #expect(capabilities.locality == .onDevice)
        #expect(!capabilities.locality.tier.leavesOwnerDevices)
        _ = await provider.reachability() // depends on the host; must not crash
        let request = AIRequest(purpose: .triage, inputs: [ClassifiedPayload("x", dataClass: .college)])
        #expect(try provider.encodeRequest(request, model: capabilities.defaultModel) == nil)
        let call = RoutedCall(request: request, effectiveClass: .college, ledgerEntryID: nil, model: capabilities.defaultModel, tier: .onDevice, wirePayload: nil)
        await #expect(throws: AIError.provider(.unavailable)) { try await provider.complete(call) }
    }

    @Test func defaultStreamYieldsOneCompletedEvent() async throws {
        let provider = RecordingProvider(.macLocal)
        let request = AIRequest(purpose: .triage, inputs: [ClassifiedPayload("x", dataClass: .publicContent)])
        let call = RoutedCall(request: request, effectiveClass: .publicContent, ledgerEntryID: nil, model: ModelID("m"), tier: .macLocal, wirePayload: nil)
        var events: [LLMEvent] = []
        for try await event in provider.stream(call) { events.append(event) }
        guard events.count == 1, case let .completed(response) = events[0] else { Issue.record("expected one completed event"); return }
        #expect(response.text == "ok")

        let failing = RecordingProvider(.macLocal, failure: .provider(.network))
        await #expect(throws: AIError.self) { for try await _ in failing.stream(call) {} }
    }

    @Test func localityTiersAndRegions() {
        #expect(DataLocality.anthropicCloud(region: "us").tier == .anthropicCloud)
        #expect(DataLocality.anthropicCloud(region: "us").region == "us")
        #expect(DataLocality.macLocal.region == nil)
        #expect(DataLocality.applePCC.tier == .applePCC)
        #expect(DataLocality.selfHostedInstitutional.tier == .selfHostedInstitutional)
    }

    @Test func errorsDescribeThemselvesWithoutContent() {
        let errors: [AIError] = [
            .boundaryViolation(requested: .anthropicCloud, reason: .collegeBoundary), .noPermittedProvider,
            .ledgerWriteFailed, .modelNotOffered, .provider(.http(status: 503)), .provider(.missingAPIKey),
            .provider(.network), .provider(.timedOut), .provider(.decoding), .provider(.unavailable), .provider(.misconfigured),
        ]
        #expect(Set(errors.map(\.logDescription)).count == errors.count)
        #expect(ModelID("claude-haiku-5-5").logDescription == "claude-haiku-5-5")
        #expect(ProviderID("anthropic").logDescription == "anthropic")
        #expect(AIPurpose.allCases.allSatisfy { !$0.logDescription.isEmpty })
        #expect(ContentKind.rawBody.logDescription == "rawBody")
    }

    @Test func idsCodeAsPlainStrings() throws {
        let data = try JSONEncoder().encode([ModelID("a"), ModelID("b")])
        #expect(String(decoding: data, as: UTF8.self) == #"["a","b"]"#)
        #expect(try JSONDecoder().decode([ProviderID].self, from: Data(#"["x"]"#.utf8)) == [ProviderID("x")])
    }
}
