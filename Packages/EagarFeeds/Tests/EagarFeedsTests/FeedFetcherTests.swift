import Foundation
import Synchronization
import Testing
@testable import EagarFeeds

/// Returns scripted responses in order and records every request. Never touches the network.
final class ScriptedTransport: HTTPTransport {
    enum Step: Sendable {
        case respond(HTTPResponse)
        case fail(FeedFetchError)
    }

    private let state: Mutex<(steps: [Step], requests: [URLRequest])>

    init(_ steps: [Step]) {
        state = Mutex((steps, []))
    }

    func send(_ request: URLRequest) async throws(FeedFetchError) -> HTTPResponse {
        let step = state.withLock { state -> Step in
            state.requests.append(request)
            return state.steps.isEmpty ? .fail(.transport) : state.steps.removeFirst()
        }
        switch step {
        case let .respond(response): return response
        case let .fail(error): throw error
        }
    }

    var requests: [URLRequest] { state.withLock { $0.requests } }
}

final class SleepRecorder: Sendable {
    private let delays = Mutex<[Duration]>([])
    var all: [Duration] { delays.withLock { $0 } }
    var sleeper: FeedFetcher.Sleeper { { [self] duration in delays.withLock { $0.append(duration) } } }
}

struct FeedFetcherTests {
    let url = URL(string: "https://bookings.example.org/api/v1/me/bookings")!

    private func fetcher(_ steps: [ScriptedTransport.Step], policy: RetryPolicy = .default) -> (FeedFetcher, ScriptedTransport, SleepRecorder) {
        let transport = ScriptedTransport(steps)
        let sleeps = SleepRecorder()
        return (FeedFetcher(transport: transport, policy: policy, sleep: sleeps.sleeper), transport, sleeps)
    }

    @Test func okReturnsBodyAndETagAndSendsHeaders() async throws {
        let (fetcher, transport, _) = fetcher([.respond(HTTPResponse(status: 200, headers: ["ETag": "\"v2\""], body: Data("x".utf8)))])
        let result = try await fetcher.get(url, bearer: "synthetic-token", etag: "\"v1\"", accept: "application/json")
        #expect(result == .modified(body: Data("x".utf8), etag: "\"v2\""))
        let request = try #require(transport.requests.first)
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer synthetic-token")
        #expect(request.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(request.timeoutInterval == 30)
    }

    @Test func notModifiedOn304() async throws {
        let (fetcher, _, _) = fetcher([.respond(HTTPResponse(status: 304))])
        #expect(try await fetcher.get(url, etag: "\"v1\"") == .notModified)
    }

    @Test(arguments: [(401, FeedFetchError.unauthorised), (403, .forbidden), (404, .notFound), (410, .gone)])
    func permanentStatusesAreNotRetried(status: Int, expected: FeedFetchError) async {
        let (fetcher, transport, sleeps) = fetcher([.respond(HTTPResponse(status: status)), .respond(HTTPResponse(status: 200))])
        await #expect(throws: expected) { try await fetcher.get(url) }
        #expect(transport.requests.count == 1)
        #expect(sleeps.all.isEmpty)
    }

    @Test func serverErrorsRetryWithExponentialBackoff() async throws {
        let (fetcher, transport, sleeps) = fetcher([
            .respond(HTTPResponse(status: 503)), .fail(.timeout), .respond(HTTPResponse(status: 200, body: Data("ok".utf8))),
        ])
        let result = try await fetcher.get(url)
        #expect(result == .modified(body: Data("ok".utf8), etag: nil))
        #expect(transport.requests.count == 3)
        #expect(sleeps.all == [.seconds(2), .seconds(4)])
    }

    @Test func retryBudgetExhaustedThrowsLastError() async {
        let (fetcher, transport, _) = fetcher([.fail(.timeout), .fail(.timeout), .fail(.offline), .respond(HTTPResponse(status: 200))])
        await #expect(throws: FeedFetchError.offline) { try await fetcher.get(url) }
        #expect(transport.requests.count == 3)
    }

    @Test func rateLimitHonoursRetryAfterWithinCap() async throws {
        let policy = RetryPolicy(maxAttempts: 2, baseDelay: .seconds(1), maxDelay: .seconds(10))
        let (fetcher, _, sleeps) = fetcher([.respond(HTTPResponse(status: 429, headers: ["Retry-After": "120"])), .respond(HTTPResponse(status: 304))], policy: policy)
        #expect(try await fetcher.get(url) == .notModified)
        #expect(sleeps.all == [.seconds(10)])
    }

    @Test func rateLimitAfterBudgetIsTyped() async {
        let (fetcher, _, _) = fetcher([.respond(HTTPResponse(status: 429, headers: ["retry-after": "5"]))], policy: RetryPolicy(maxAttempts: 1))
        await #expect(throws: FeedFetchError.rateLimited(retryAfter: 5)) { try await fetcher.get(url) }
    }

    @Test func plainHTTPIsRefusedWithoutARequest() async {
        let (fetcher, transport, _) = fetcher([.respond(HTTPResponse(status: 200))])
        await #expect(throws: FeedFetchError.insecureURL) { try await fetcher.get(URL(string: "http://bookings.example.org/x")!) }
        #expect(transport.requests.isEmpty)
    }

    @Test func backoffIsCapped() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: .seconds(2), maxDelay: .seconds(30))
        #expect(policy.delay(afterAttempt: 1) == .seconds(2))
        #expect(policy.delay(afterAttempt: 3) == .seconds(8))
        #expect(policy.delay(afterAttempt: 9) == .seconds(30))
        #expect(policy.delay(afterAttempt: 1, retryAfterSeconds: 7) == .seconds(7))
    }

    @Test func errorsAreLogSafe() {
        #expect(FeedFetchError.rateLimited(retryAfter: nil).logDescription == "rateLimited(nil)")
        #expect(FeedFetchError.server(status: 502).logDescription == "server(502)")
    }
}
