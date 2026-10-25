import EagarAITestSupport
import EagarCore
import Foundation
import Testing
@testable import EagarAI

struct ProviderStubTests {
    @Test func appleOnDeviceIsLocalAndHasNoWireFormat() async throws {
        let provider = AppleOnDeviceProvider()
        let capabilities = await provider.capabilities()
        #expect(capabilities.locality == .onDevice)
        #expect(!capabilities.locality.tier.leavesOwnerDevices)
        #expect(capabilities.maxContextTokens == AppleOnDeviceProvider.contextTokens) // read at runtime, never assumed
        let request = AIRequest(purpose: .triage, inputs: [ClassifiedPayload("x", dataClass: .college)])
        #expect(try provider.encodeRequest(request, model: capabilities.defaultModel) == nil)
        let wrongTier = RoutedCall(request: request, effectiveClass: .college, ledgerEntryID: nil, model: capabilities.defaultModel, tier: .macLocal, wirePayload: nil)
        await #expect(throws: AIError.provider(.misconfigured)) { try await provider.complete(wrongTier) }
        var schemaRequest = request
        schemaRequest.outputSchema = JSONSchema(name: "S", json: Data("{}".utf8), dataClass: .publicContent)
        let withSchema = RoutedCall(request: schemaRequest, effectiveClass: .college, ledgerEntryID: nil, model: capabilities.defaultModel, tier: .onDevice, wirePayload: nil)
        await #expect(throws: AIError.provider(.misconfigured)) { try await provider.complete(withSchema) }
    }

    /// FR-AI-06: sizing is arithmetic against the runtime context, never a fixed 4,096 or 8,192.
    @Test func appleOnDeviceSizing() {
        let request = AIRequest(purpose: .triage, inputs: [ClassifiedPayload("one", dataClass: .personal), ClassifiedPayload("two", dataClass: .personal)])
        #expect(AppleOnDeviceProvider.prompt(for: request) == "one\n\ntwo")
        #expect(AppleOnDeviceProvider.fits(needed: 3_000, output: 1_000, context: 4_096))
        #expect(!AppleOnDeviceProvider.fits(needed: 3_200, output: 1_000, context: 4_096))
        #expect(AppleOnDeviceProvider.fits(needed: 7_000, output: 1_000, context: 8_192))
        #expect(AppleOnDeviceProvider.estimatedTokens("") == 0)
        #expect(AppleOnDeviceProvider.estimatedTokens("abcd") == 2)
    }

    /// A real on-device call, run only where Apple Intelligence is available (e.g. Mark's Mac).
    /// Simulators can report Apple Intelligence as available without model assets (tiny context),
    /// so the live call also needs a usable context.
    @Test(.enabled(if: AppleOnDeviceProvider.isAvailable && AppleOnDeviceProvider.contextTokens >= 1_024, "Apple Intelligence not usable here"))
    func appleOnDeviceLiveCall() async throws {
        let provider = AppleOnDeviceProvider()
        let request = AIRequest(purpose: .triage, inputs: [ClassifiedPayload("Reply with the single word OK.", dataClass: .publicContent)], maxOutputTokens: 16)
        let call = RoutedCall(request: request, effectiveClass: .publicContent, ledgerEntryID: nil, model: ModelID("apple.systemLanguageModel"), tier: .onDevice, wirePayload: nil)
        let response = try await provider.complete(call)
        #expect(response.stopReason == .refusal || !response.text.isEmpty)
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
            .provider(.contextTooLarge), .provider(.keychain(status: -1)),
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
