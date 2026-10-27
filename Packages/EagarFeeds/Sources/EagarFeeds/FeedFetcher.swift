import EagarCore
import Foundation

/// Errors from fetching a feed. Content-free, so they may be logged and shown.
public enum FeedFetchError: Error, Equatable, Sendable, LogSafe {
    /// `401`: the token was rotated or revoked (Appendix E.2). The user must re-enter it.
    case unauthorised
    /// `403`: the token lacks the scope for this endpoint.
    case forbidden
    /// `410 Gone`: the feed was revoked (Appendix E.2).
    case gone
    /// `404`: the endpoint does not exist on this server.
    case notFound
    /// `429` after the retry budget, with the server's `Retry-After` in seconds if given.
    case rateLimited(retryAfter: Int?)
    /// Any other non-success status after the retry budget.
    case server(status: Int)
    /// The request timed out after the retry budget.
    case timeout
    /// No network connection.
    case offline
    /// Another transport failure (TLS, DNS, connection reset).
    case transport
    /// Only `https` URLs are fetched (Appendix E.1).
    case insecureURL
    /// The response was not HTTP or could not be read.
    case invalidResponse

    public var logDescription: String {
        switch self {
        case .unauthorised: "unauthorised"
        case .forbidden: "forbidden"
        case .gone: "gone"
        case .notFound: "notFound"
        case let .rateLimited(after): "rateLimited(\(after.map(String.init) ?? "nil"))"
        case let .server(status): "server(\(status))"
        case .timeout: "timeout"
        case .offline: "offline"
        case .transport: "transport"
        case .insecureURL: "insecureURL"
        case .invalidResponse: "invalidResponse"
        }
    }

    /// Whether another attempt may succeed.
    var isTransient: Bool {
        switch self {
        case .timeout, .offline, .transport, .rateLimited: true
        case let .server(status): status >= 500
        default: false
        }
    }
}

/// An HTTP response, reduced to what the pipeline uses. Header names are lower-cased.
public struct HTTPResponse: Sendable, Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data

    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status
        self.headers = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        self.body = body
    }

    public func header(_ name: String) -> String? { headers[name.lowercased()] }
}

/// Sends one HTTP request. Tests inject fakes; no test touches the network.
///
/// Implementations throw only transport errors (`timeout`, `offline`, `transport`,
/// `invalidResponse`); status codes are returned, not thrown.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws(FeedFetchError) -> HTTPResponse
}

/// `URLSession` transport with an ephemeral configuration: no cookies, no URL cache, no
/// credential storage, so a feed's response or token is never written to disk by the system.
public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: configuration)
    }

    public func send(_ request: URLRequest) async throws(FeedFetchError) -> HTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw FeedFetchError.invalidResponse }
            var headers: [String: String] = [:]
            for (key, value) in http.allHeaderFields {
                if let key = key as? String, let value = value as? String { headers[key] = value }
            }
            return HTTPResponse(status: http.statusCode, headers: headers, body: data)
        } catch let error as FeedFetchError {
            throw error
        } catch let error as URLError {
            switch error.code {
            case .timedOut: throw .timeout
            case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: throw .offline
            default: throw .transport
            }
        } catch {
            throw .transport
        }
    }
}

/// Timeout and retry with exponential backoff (CLAUDE.md: every external integration).
public struct RetryPolicy: Sendable, Hashable {
    /// Total attempts, including the first.
    public let maxAttempts: Int
    /// Delay before the second attempt; doubled for each further one.
    public let baseDelay: Duration
    /// Upper bound for any single delay, including a server's `Retry-After`.
    public let maxDelay: Duration
    /// Per-request timeout.
    public let timeout: Duration

    public init(maxAttempts: Int = 3, baseDelay: Duration = .seconds(2), maxDelay: Duration = .seconds(60), timeout: Duration = .seconds(30)) {
        self.maxAttempts = max(1, maxAttempts)
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.timeout = timeout
    }

    public static let `default` = RetryPolicy()

    /// The delay after failed attempt `attempt` (1-based): `baseDelay · 2^(attempt-1)`, capped.
    public func delay(afterAttempt attempt: Int, retryAfterSeconds: Int? = nil) -> Duration {
        if let retryAfterSeconds { return min(.seconds(max(0, retryAfterSeconds)), maxDelay) }
        let factor = 1 << min(max(0, attempt - 1), 20)
        return min(baseDelay * factor, maxDelay)
    }
}

/// The result of a conditional fetch.
public enum FeedFetchResult: Sendable, Equatable {
    /// `200` with the body and the new `ETag`, if the server sent one.
    case modified(body: Data, etag: String?)
    /// `304 Not Modified` for the `If-None-Match` sent.
    case notModified
}

/// Conditional GET with timeout, retry and typed errors: the network half of the feed pipeline.
public struct FeedFetcher: Sendable {
    public typealias Sleeper = @Sendable (Duration) async throws -> Void

    private let transport: any HTTPTransport
    private let policy: RetryPolicy
    private let sleep: Sleeper
    private let log = EagarLog(.feeds)

    /// - Parameter sleep: waits between attempts; tests pass a recorder that returns at once.
    public init(transport: any HTTPTransport = URLSessionTransport(), policy: RetryPolicy = .default, sleep: @escaping Sleeper = { try await Task.sleep(for: $0) }) {
        self.transport = transport
        self.policy = policy
        self.sleep = sleep
    }

    /// GETs `url`. Sends `If-None-Match` when `etag` is given and returns `.notModified` on 304.
    /// Retries transient failures (timeouts, connection errors, 5xx, 429) with backoff; never
    /// retries 401, 403, 404 or 410.
    ///
    /// - Parameter bearer: the raw token for `Authorization: Bearer`, revealed by the caller at
    ///   the point of use. It is never logged.
    public func get(_ url: URL, bearer: String? = nil, etag: String? = nil, accept: String? = nil) async throws(FeedFetchError) -> FeedFetchResult {
        guard url.scheme?.lowercased() == "https" else { throw .insecureURL }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = Double(policy.timeout.components.seconds)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }

        var attempt = 0
        while true {
            attempt += 1
            let failure: FeedFetchError
            var retryAfter: Int?
            do {
                let response = try await transport.send(request)
                switch response.status {
                case 200 ..< 300:
                    return .modified(body: response.body, etag: response.header("ETag"))
                case 304:
                    return .notModified
                case 401: failure = .unauthorised
                case 403: failure = .forbidden
                case 404: failure = .notFound
                case 410: failure = .gone
                case 429:
                    retryAfter = response.header("Retry-After").flatMap { Int($0.trimmingCharacters(in: .whitespaces)) }
                    failure = .rateLimited(retryAfter: retryAfter)
                default: failure = .server(status: response.status)
                }
            } catch {
                failure = error
            }
            guard failure.isTransient, attempt < policy.maxAttempts else {
                log.notice("feed fetch failed: \(failure) after \(attempt) attempt(s)")
                throw failure
            }
            do {
                try await sleep(policy.delay(afterAttempt: attempt, retryAfterSeconds: retryAfter))
            } catch {
                throw failure
            }
        }
    }
}
