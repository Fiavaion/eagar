import CoreGraphics
import EagarAI
import EagarAITestSupport
import EagarCore
import EagarLedger
import Foundation
import Synchronization
import Testing
@testable import EagarMoney

// MARK: - Test doubles

/// Returns fixed lines instead of running Vision.
struct FixedTextRecognizer: TextRecognizing {
    let lines: [String]
    func recognizeText(in image: CGImage) async throws(TrialImportError) -> [String] { lines }
}

/// An on-device provider that answers with scripted text and records what it was sent.
final class ScriptedProvider: LLMProvider {
    let id = ProviderID("scripted.onDevice")
    let locality: DataLocality
    private let reply: String
    private let calls = Mutex<[RoutedCall]>([])

    init(reply: String, locality: DataLocality = .onDevice) {
        self.reply = reply
        self.locality = locality
    }

    var recorded: [RoutedCall] { calls.withLock { $0 } }

    func capabilities() async -> ProviderCapabilities {
        ProviderCapabilities(locality: locality, defaultModel: ModelID("apple.onDevice"), maxContextTokens: 4096)
    }

    func reachability() async -> Reachability { .reachable }
    func encodeRequest(_ request: AIRequest, model: ModelID) throws(AIError) -> Data? { nil }

    func complete(_ call: RoutedCall) async throws(AIError) -> LLMResponse {
        calls.withLock { $0.append(call) }
        return LLMResponse(text: reply, model: call.model)
    }
}

final class CapturingLogSink: LogSink {
    private let records = Mutex<[LogRecord]>([])
    func receive(_ record: LogRecord) { records.withLock { $0.append(record) } }
    var all: [LogRecord] { records.withLock { $0 } }
}

let catalog = try! ModelCatalog.bundled()

func makeRouter(_ providers: [any LLMProvider], ledger: InMemoryLedger = InMemoryLedger(), policy: PolicySnapshot = PolicySnapshot()) -> AIRouter {
    AIRouter(providers: providers, ledger: ledger, policy: StaticPolicySource(policy), catalog: catalog)
}

private let blank: CGImage = {
    let context = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    return context.makeImage()!
}()

private let spotifyLines = ["Spotify", "Premium Individual", "Your trial ends 5 Nov 2026.", "Then €11.99/month. Cancel anytime."]

// MARK: - Vision OCR on the fixtures (acceptance: ≥ 8/10)

/// Serialised: Vision runs on the Neural Engine/GPU and is slow when twelve run at once.
@Suite(.serialized)
struct VisionImportTests {
    let cal = TestCalendars.dublin

    /// M2 acceptance (FR-TRIAL-03): screenshot import of fixture receipts extracts service,
    /// price and date with the Vision fallback (no model) for at least 8 of 10 fixtures.
    @Test func FR_TRIAL_03_visionFallbackScoresAtLeast8of10() async throws {
        let importer = TrialScreenshotImporter(recognizer: VisionTextRecognizer(), router: nil, mode: .parserOnly, calendar: cal)
        var correct: [String] = []
        var missed: [String] = []
        for fixture in ReceiptFixture.all {
            let result = try await importer.importTrial(fromImageData: fixture.imageData())
            #expect(result.method == .parser)
            #expect(result.dataClass == .personal)
            if fixture.matches(result.draft, calendar: cal) {
                correct.append(fixture.file)
            } else {
                missed.append("\(fixture.file): \(result.draft.service ?? "-") \(result.draft.price.map { "\($0)" } ?? "-") \(result.draft.renewsAt.map { ReceiptFixture.dayString($0, cal) } ?? "-")")
            }
        }
        let total = ReceiptFixture.all.count
        // Scaled to the acceptance criterion's "8 of 10" for any fixture count ≥ 10.
        #expect(total >= 10)
        #expect(correct.count * 10 >= total * 8, "score \(correct.count)/\(total); missed: \(missed)")
        print("FR-TRIAL-03 Vision fallback fixture score: \(correct.count)/\(total)")
    }

    @Test func visionReadsLinesTopToBottom() async throws {
        let fixture = ReceiptFixture.all[2]
        let lines = try await VisionTextRecognizer().recognizeText(in: fixture.cgImage())
        #expect(lines.first?.lowercased().contains("spotify") == true)
        #expect(lines.count >= fixture.lines.count - 1)
    }
}

// MARK: - Importer behaviour and boundaries

struct ScreenshotImportTests {
    let cal = TestCalendars.dublin

    @Test func unreadableDataAndBlankImagesFail() async {
        let importer = TrialScreenshotImporter(recognizer: FixedTextRecognizer(lines: ["", "  "]), router: nil, calendar: cal)
        await #expect(throws: TrialImportError.unreadableImage) { try await importer.importTrial(fromImageData: Data("nope".utf8)) }
        await #expect(throws: TrialImportError.noText) { try await importer.importTrial(from: blank) }
    }

    @Test func sharedTextImports() async {
        let importer = TrialScreenshotImporter(router: nil, calendar: cal)
        let result = await importer.importTrial(fromText: spotifyLines.joined(separator: "\n"))
        #expect(result.draft.service == "Spotify")
        #expect(result.draft.price == Decimal(string: "11.99"))
        #expect(result.draft.isTrial)
        #expect(result.method == .parser)
    }

    @Test func FR_TRIAL_03_validModelAnswerIsUsed() async throws {
        let provider = ScriptedProvider(reply: #"Here: {"service":"Spotify","price":"11.99","currency":"EUR","date":"2026-11-05","period":"monthly"}"#)
        let importer = TrialScreenshotImporter(recognizer: FixedTextRecognizer(lines: spotifyLines), router: makeRouter([provider]), calendar: cal)
        let result = try await importer.importTrial(from: blank)
        #expect(result.method == .onDeviceModel)
        #expect(result.draft.service == "Spotify")
        #expect(result.draft.price == Decimal(string: "11.99"))
        #expect(result.draft.renewsAt == TestCalendars.date(2026, 11, 5))
        #expect(result.draft.period == .monthly)
        let call = try #require(provider.recorded.first)
        #expect(call.tier == .onDevice)
        #expect(call.request.purpose == .extraction)
        #expect(call.request.inputs.allSatisfy { $0.dataClass == .personal && $0.kind == .rawBody })
    }

    /// The model invents a price and a date that are not in the text: both are dropped and the
    /// parser's values used instead.
    @Test func FR_TRIAL_03_inventedModelValuesAreDropped() async throws {
        let provider = ScriptedProvider(reply: #"{"service":"Spotify","price":"9.99","currency":"EUR","date":"2026-12-25","period":"monthly"}"#)
        let importer = TrialScreenshotImporter(recognizer: FixedTextRecognizer(lines: spotifyLines), router: makeRouter([provider]), calendar: cal)
        let result = try await importer.importTrial(from: blank)
        #expect(result.method == .combined)
        #expect(result.draft.price == Decimal(string: "11.99"))
        #expect(result.draft.renewsAt == TestCalendars.date(2026, 11, 5))
    }

    @Test func garbageModelAnswerFallsBackToParser() async throws {
        let provider = ScriptedProvider(reply: "I cannot help with that")
        let importer = TrialScreenshotImporter(recognizer: FixedTextRecognizer(lines: spotifyLines), router: makeRouter([provider]), calendar: cal)
        let result = try await importer.importTrial(from: blank)
        #expect(result.method == .parser)
        #expect(result.draft.hasCoreFields)
    }

    /// Trial extraction never reaches a cloud tier: every tier registered, Claude consented
    /// for the source, and still only the on-device provider is called. The ledger holds one
    /// model-call entry, on-device, with no payload bytes (nothing left the device).
    @Test func Boundary_trialExtractionStaysOnDevice() async throws {
        let providers = RecordingProvider.oneOfEach()
        let ledger = InMemoryLedger()
        let source = SourceID()
        let policy = PolicySnapshot(
            settings: PolicySettings(meithealPersonalEnabled: true, applePCCForRawPersonal: true),
            sourceModes: [source: .cloudAllowed],
            consents: [ConsentKey(sourceID: source, purpose: .extraction, tier: .anthropicCloud): UUID()]
        )
        let importer = TrialScreenshotImporter(
            recognizer: FixedTextRecognizer(lines: spotifyLines), router: makeRouter(providers, ledger: ledger, policy: policy),
            sourceID: source, calendar: cal
        )
        _ = try await importer.importTrial(from: blank)
        let called = providers.filter { !$0.recordedCalls.isEmpty }.map(\.locality.tier)
        #expect(called == [.onDevice])
        #expect(ledger.entries.count == 1)
        let entry = try #require(ledger.entries.first)
        #expect(entry.draft.kind == .modelCall)
        #expect(entry.draft.tier == .onDevice)
        #expect(entry.draft.payload == nil)
        #expect(entry.completion?.outcome == .succeeded)
    }

    /// With the on-device model unreachable the router may not fall back to the Mac, PCC or
    /// Claude: nothing is called, nothing is ledgered, and the parser produces the draft.
    @Test func Boundary_noOnDeviceModelMeansParserNotCloud() async throws {
        let cloudish = [RecordingProvider(.onDevice, reachable: false), RecordingProvider(.macLocal), RecordingProvider(.applePCC),
                        RecordingProvider(.selfHostedInstitutional), RecordingProvider(.anthropicCloud(region: "global"))]
        let ledger = InMemoryLedger()
        let source = SourceID()
        let policy = PolicySnapshot(
            settings: PolicySettings(meithealPersonalEnabled: true, applePCCForRawPersonal: true),
            sourceModes: [source: .cloudAllowed],
            consents: [ConsentKey(sourceID: source, purpose: .extraction, tier: .anthropicCloud): UUID()]
        )
        let importer = TrialScreenshotImporter(
            recognizer: FixedTextRecognizer(lines: spotifyLines), router: makeRouter(cloudish, ledger: ledger, policy: policy),
            sourceID: source, calendar: cal
        )
        let result = try await importer.importTrial(from: blank)
        #expect(cloudish.allSatisfy { $0.recordedCalls.isEmpty })
        #expect(ledger.entries.isEmpty)
        #expect(result.method == .parser)
        #expect(result.draft.hasCoreFields)
    }

    /// Kill switch engaged: no provider call, parser draft (FR-CORE-07).
    @Test func Boundary_killSwitchFallsBackToParser() async throws {
        let provider = RecordingProvider(.onDevice)
        let router = makeRouter([provider])
        await router.halt()
        let importer = TrialScreenshotImporter(recognizer: FixedTextRecognizer(lines: spotifyLines), router: router, calendar: cal)
        let result = try await importer.importTrial(from: blank)
        #expect(provider.recordedCalls.isEmpty)
        #expect(result.method == .parser)
        #expect(result.draft.service == "Spotify")
    }

    /// Parser-only mode makes zero model calls of any kind (invariant 3) and ledgers nothing.
    @Test func Boundary_parserOnlyMakesNoModelCall() async throws {
        let providers = RecordingProvider.oneOfEach()
        let ledger = InMemoryLedger()
        let importer = TrialScreenshotImporter(
            recognizer: FixedTextRecognizer(lines: spotifyLines), router: makeRouter(providers, ledger: ledger),
            mode: .parserOnly, calendar: cal
        )
        _ = try await importer.importTrial(from: blank)
        #expect(providers.allSatisfy { $0.recordedCalls.isEmpty })
        #expect(ledger.entries.isEmpty)
    }

    /// A rules-only source is refused by the router (one blocked entry, no call); the parser
    /// still produces the draft.
    @Test func Boundary_rulesOnlySourceIsRefusedByTheRouter() async throws {
        let provider = RecordingProvider(.onDevice)
        let ledger = InMemoryLedger()
        let source = SourceID()
        let importer = TrialScreenshotImporter(
            recognizer: FixedTextRecognizer(lines: spotifyLines),
            router: makeRouter([provider], ledger: ledger, policy: PolicySnapshot(sourceModes: [source: .rulesOnly])),
            sourceID: source, calendar: cal
        )
        let result = try await importer.importTrial(from: blank)
        #expect(provider.recordedCalls.isEmpty)
        #expect(ledger.entries.map(\.draft.kind) == [.blocked])
        #expect(result.method == .parser)
    }

    /// No receipt content reaches the logs (invariant 7): service, price, date and the
    /// recognised lines never appear in any captured log line.
    @Test func Boundary_importLogsNoContent() async throws {
        let sink = CapturingLogSink()
        let token = EagarLog.addSink(sink)
        defer { EagarLog.removeSink(token) }

        let secretLines = ["Zorblax Streaming", "Your trial ends 7 Nov 2026", "Then €17.43/month", "card ending 4242"]
        let withModel = TrialScreenshotImporter(
            recognizer: FixedTextRecognizer(lines: secretLines),
            router: makeRouter([ScriptedProvider(reply: #"{"service":"Zorblax Streaming","price":"17.43","currency":"EUR","date":"2026-11-07","period":"monthly"}"#)]),
            calendar: cal
        )
        _ = try await withModel.importTrial(from: blank)
        let halted = makeRouter([RecordingProvider(.onDevice)])
        await halted.halt()
        _ = try await TrialScreenshotImporter(recognizer: FixedTextRecognizer(lines: secretLines), router: halted, calendar: cal).importTrial(from: blank)
        _ = try? await TrialScreenshotImporter(recognizer: FixedTextRecognizer(lines: []), router: nil, calendar: cal).importTrial(from: blank)

        let text = sink.all.map(\.text).joined(separator: "\n").lowercased()
        #expect(text.contains("trial import"))
        for needle in ["zorblax", "17.43", "17,43", "4242", "nov", "2026"] {
            #expect(!text.contains(needle), "log contains \(needle)")
        }
    }
}
