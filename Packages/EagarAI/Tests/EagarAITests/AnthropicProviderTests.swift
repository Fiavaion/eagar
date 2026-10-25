import EagarAITestSupport
import EagarCore
import EagarLedger
import EagarSecurity
import EagarStore
import Foundation
import Synchronization
import Testing
@testable import EagarAI

// MARK: - Test doubles

final class MemorySecrets: SecretStore {
    private let values = Mutex<[String: String]>([:])
    init(_ initial: [SecretKey: String] = [:]) {
        values.withLock { dict in for (key, value) in initial { dict[key.account] = value } }
    }
    func set(_ secret: Secret, for key: SecretKey) throws(SecurityError) { values.withLock { $0[key.account] = secret.reveal() } }
    func get(_ key: SecretKey) throws(SecurityError) -> Secret? { values.withLock { $0[key.account] }.map(Secret.init) }
    func delete(_ key: SecretKey) throws(SecurityError) { _ = values.withLock { $0.removeValue(forKey: key.account) } }
}

struct AllowAuth: DeviceOwnerAuthenticating {
    func authenticate(reason: String) async throws(SecurityError) -> AuthenticationProof { AuthenticationProof(at: Date(), method: .passcode) }
}

struct CapturedRequest: Sendable {
    let url: URL?
    let headers: [String: String]
    let body: Data
}

/// Serves canned responses; the handler is async so it can inspect the ledger mid-request.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    // SAFETY: test-only; handler and log are guarded by Mutex.
    typealias Handler = @Sendable (CapturedRequest) async -> (Int, [String: String], Data)
    static let handler = Mutex<Handler?>(nil)
    static let captured = Mutex<[CapturedRequest]>([])

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let request = self.request
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = stream.read(&buffer, maxLength: buffer.count)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            stream.close()
        }
        let captured = CapturedRequest(url: request.url, headers: request.allHTTPHeaderFields ?? [:], body: body)
        Self.captured.withLock { $0.append(captured) }
        let handler = Self.handler.withLock { $0 }
        let client = self.client
        let me = self
        Task { @Sendable [client, me, request, handler, captured] in
            let (status, headers, data) = await handler?(captured) ?? (500, [:], Data())
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(me, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(me, didLoad: data)
            client?.urlProtocolDidFinishLoading(me)
        }
    }

    static func reset(_ newHandler: Handler?) {
        handler.withLock { $0 = newHandler }
        captured.withLock { $0.removeAll() }
    }
}

private let canaryKey = "test-canary-key-7f3a9c2e"

private func okBody(model: String = "claude-haiku-5-5") -> Data {
    Data("""
    {"id":"msg_1","type":"message","role":"assistant","model":"\(model)",
     "content":[{"type":"thinking","thinking":""},{"type":"text","text":"OK"}],
     "stop_reason":"end_turn",
     "usage":{"input_tokens":20,"output_tokens":3,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}
    """.utf8)
}

private func provider(key: String? = canaryKey) -> AnthropicProvider {
    AnthropicProvider(
        secrets: MemorySecrets(key.map { [.anthropicAPIKey: $0] } ?? [:]),
        session: StubURLProtocol.session(),
        retryDelays: [.zero, .zero]
    )
}

// MARK: - Tests

@Suite(.serialized)
struct AnthropicProviderTests {
    /// M0 acceptance: a ledger entry (with the exact payload) is persisted before every Claude
    /// request; the stub asserts it while the request is in flight.
    @Test func ledgerEntryIsPersistedBeforeTheRequest() async throws {
        let stores = try EagarStores(location: .inMemory, models: [LedgerEntry.self])
        let ledger = PrivacyLedger(stores: stores, authenticator: AllowAuth())
        let sawEntry = Mutex(false)
        StubURLProtocol.reset { request in
            let records = (try? await ledger.records()) ?? []
            let pending = records.first { $0.outcome == .pending && $0.kind == .keyTest }
            sawEntry.withLock {
                $0 = pending?.payload == String(decoding: request.body, as: UTF8.self) && pending?.tier == .anthropicCloud
            }
            return (200, ["content-type": "application/json"], okBody())
        }
        let router = makeRouter([provider()], ledger: ledger)

        let outcome = await KeyTester.run(using: router)

        #expect(sawEntry.withLock { $0 }, "ledger entry was not present, or payload differed, when the request was sent")
        guard case let .valid(model, cost) = outcome else { Issue.record("unexpected \(outcome)"); return }
        #expect(model == ModelID("claude-haiku-5-5"))
        #expect(cost == 4) // 20 × $0.10 + 3 × $0.50 per MTok = 3.5 µ$, rounded
        let record = try #require(try await ledger.records().first)
        #expect(record.kind == .keyTest)
        #expect(record.outcome == .succeeded)
        #expect(record.inputTokens == 20 && record.outputTokens == 3)
        #expect(record.payload?.contains("Reply with the single word OK.") == true)
        #expect(record.payload?.contains(canaryKey) == false)

        let sent = try #require(StubURLProtocol.captured.withLock { $0.first })
        #expect(sent.url == AnthropicProvider.endpoint)
        #expect(sent.headers["x-api-key"] == canaryKey)
        #expect(sent.headers["anthropic-version"] == "2026-10-21")
        #expect(sent.headers["Content-Type"] ?? sent.headers["content-type"] == "application/json")
    }

    @Test func ledgerFailureMeansNoRequest() async throws {
        StubURLProtocol.reset { _ in (200, [:], okBody()) }
        let router = makeRouter([provider()], ledger: InMemoryLedger(failWrites: true))
        let outcome = await KeyTester.run(using: router)
        #expect(outcome == .failed(.ledgerWriteFailed))
        #expect(StubURLProtocol.captured.withLock { $0.isEmpty })
    }

    /// The BYOK key never appears in any log line, on success or failure (log-capture test with a canary key).
    @Test func apiKeyNeverLogged() async throws {
        let sink = CapturingSink()
        let token = EagarLog.addSink(sink)
        defer { EagarLog.removeSink(token) }

        StubURLProtocol.reset { _ in (200, [:], okBody()) }
        _ = await KeyTester.run(using: makeRouter([provider()]))
        StubURLProtocol.reset { _ in (500, [:], Data("{\"error\":\"\(canaryKey)\"}".utf8)) }
        _ = await KeyTester.run(using: makeRouter([provider()]))
        StubURLProtocol.reset { _ in (401, [:], Data()) }
        #expect(await KeyTester.run(using: makeRouter([provider()])) == .invalidKey)

        #expect(!sink.texts.isEmpty)
        #expect(sink.texts.allSatisfy { !$0.contains(canaryKey) && !$0.contains("canary") })
    }

    @Test func missingKeyMakesProviderUnavailable() async throws {
        StubURLProtocol.reset { _ in (200, [:], okBody()) }
        #expect(await provider(key: nil).reachability() == .unreachable)
        #expect(await KeyTester.run(using: makeRouter([provider(key: nil)])) == .noKey)
        #expect(StubURLProtocol.captured.withLock { $0.isEmpty })
    }

    @Test func retriesTransientFailuresThenSucceeds() async throws {
        let attempts = Mutex(0)
        StubURLProtocol.reset { _ in
            let n = attempts.withLock { $0 += 1; return $0 }
            return n < 3 ? (529, [:], Data()) : (200, [:], okBody())
        }
        guard case .valid = await KeyTester.run(using: makeRouter([provider()])) else { Issue.record("expected success"); return }
        #expect(attempts.withLock { $0 } == 3)
    }

    @Test func doesNotRetryClientErrors() async throws {
        StubURLProtocol.reset { _ in (400, [:], Data()) }
        #expect(await KeyTester.run(using: makeRouter([provider()])) == .failed(.provider(.http(status: 400))))
        #expect(StubURLProtocol.captured.withLock { $0.count } == 1)
    }

    @Test func refusesRoutedCallsThatBreakPreconditions() async throws {
        StubURLProtocol.reset { _ in (200, [:], okBody()) }
        let request = AIRequest(purpose: .triage, inputs: [ClassifiedPayload("x", dataClass: .college)])
        let body = try #require(try provider().encodeRequest(request, model: ModelID("claude-haiku-5-5")))
        let id = LedgerEntryID(rawValue: UUID(), store: .college)
        let college = RoutedCall(request: request, effectiveClass: .college, ledgerEntryID: id, model: ModelID("claude-haiku-5-5"), tier: .anthropicCloud, wirePayload: body)
        let unledgered = RoutedCall(request: request, effectiveClass: .personal, ledgerEntryID: nil, model: ModelID("claude-haiku-5-5"), tier: .anthropicCloud, wirePayload: body)
        await #expect(throws: AIError.provider(.misconfigured)) { try await provider().complete(college) }
        await #expect(throws: AIError.provider(.misconfigured)) { try await provider().complete(unledgered) }
        #expect(StubURLProtocol.captured.withLock { $0.isEmpty })
    }
}

struct AnthropicEncodingTests {
    @Test func encodesMessagesSystemSchemaAndEffortDeterministically() throws {
        let schema = JSONSchema(name: "Brief", json: Data(#"{"type":"object","additionalProperties":false,"properties":{"line":{"type":"string"}},"required":["line"]}"#.utf8))
        let request = AIRequest(
            purpose: .briefPhrase,
            inputs: [ClassifiedPayload("one", dataClass: .publicContent), ClassifiedPayload("two", dataClass: .publicContent)],
            system: ClassifiedPayload("You are Eagar.", dataClass: .publicContent),
            outputSchema: schema, maxOutputTokens: 512, effort: .low
        )
        let p = AnthropicProvider(secrets: MemorySecrets())
        let first = try #require(try p.encodeRequest(request, model: ModelID("claude-sonnet-5-5")))
        let second = try #require(try p.encodeRequest(request, model: ModelID("claude-sonnet-5-5")))
        #expect(first == second)

        let json = try JSONSerialization.jsonObject(with: first) as! [String: Any]
        #expect(json["model"] as? String == "claude-sonnet-5-5")
        #expect(json["max_tokens"] as? Int == 512)
        let messages = json["messages"] as! [[String: Any]]
        #expect(messages.count == 1 && messages[0]["role"] as? String == "user")
        #expect((messages[0]["content"] as! [[String: Any]]).compactMap { $0["text"] as? String } == ["one", "two"])
        let system = json["system"] as! [[String: Any]]
        #expect(system[0]["text"] as? String == "You are Eagar.")
        #expect((system[0]["cache_control"] as? [String: String])?["type"] == "ephemeral")
        let output = json["output_config"] as! [String: Any]
        #expect(output["effort"] as? String == "low")
        #expect((output["format"] as? [String: Any])?["type"] as? String == "json_schema")
        #expect(json["temperature"] == nil) // sampling parameters are rejected on API version 2026-10-21
    }

    @Test func emptyInputsAreRejected() {
        #expect(throws: AIError.provider(.misconfigured)) {
            try AnthropicProvider(secrets: MemorySecrets()).encodeRequest(AIRequest(purpose: .triage, inputs: []), model: ModelID("m"))
        }
    }

    @Test func decodesTextUsageAndStopReasons() throws {
        let response = try AnthropicProvider.decode(okBody(model: "claude-sonnet-5-5"))
        #expect(response.text == "OK")
        #expect(response.model == ModelID("claude-sonnet-5-5"))
        #expect(response.usage == LLMUsage(inputTokens: 20, outputTokens: 3))
        #expect(response.stopReason == .endTurn)

        let refusal = try AnthropicProvider.decode(Data(#"{"model":"m","content":[],"stop_reason":"refusal"}"#.utf8))
        #expect(refusal.stopReason == .refusal)
        #expect(refusal.usage == nil)
        #expect(throws: AIError.provider(.decoding)) { try AnthropicProvider.decode(Data("nope".utf8)) }
    }

    @Test func retryPolicy() {
        #expect(AnthropicProvider.isRetryable(.http(status: 429)))
        #expect(AnthropicProvider.isRetryable(.http(status: 529)))
        #expect(AnthropicProvider.isRetryable(.network))
        #expect(!AnthropicProvider.isRetryable(.http(status: 400)))
        #expect(!AnthropicProvider.isRetryable(.http(status: 401)))
        #expect(!AnthropicProvider.isRetryable(.missingAPIKey))
    }

    /// FR-AI-11: no Message Batches endpoint exists anywhere in the AI gateway.
    @Test func noBatchesEndpointInSources() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "../../Sources").standardized
        let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)!
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            #expect(!text.contains("messages/batches"), "\(file.lastPathComponent)")
        }
    }
}

final class CapturingSink: LogSink {
    private let records = Mutex<[String]>([])
    func receive(_ record: LogRecord) { records.withLock { $0.append(record.text) } }
    var texts: [String] { records.withLock { $0 } }
}
