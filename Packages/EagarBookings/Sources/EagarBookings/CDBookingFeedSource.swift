import EagarCore
import EagarFeeds
import EagarSecurity
import Foundation

/// The two cdbooking secrets (Appendix E.2). Both are bearer secrets and live only in the
/// Keychain, under the source's ID (FR-BOOK-01, invariant 6).
public struct CDBookingCredentials: Sendable {
    /// The per-user iCal feed URL; it embeds `feed_token`.
    public let feedURL: Secret
    /// The `api_token` for the JSON endpoint. Without it, only the iCal feed is read.
    public let apiToken: Secret?

    public init(feedURL: Secret, apiToken: Secret?) {
        self.feedURL = feedURL
        self.apiToken = apiToken
    }
}

/// Keychain storage for ``CDBookingCredentials``.
public struct CDBookingSecrets: Sendable {
    private let store: any SecretStore

    public init(store: any SecretStore) {
        self.store = store
    }

    /// Saves the pasted or scanned credentials. The feed URL must be a valid cdbooking feed
    /// URL (see ``CDBookingFeedSource/normalisedFeedURL(_:)``).
    public func save(_ credentials: CDBookingCredentials, for source: SourceID) throws(SecurityError) {
        try store.set(credentials.feedURL, for: .cdbookingFeedURL(source))
        if let token = credentials.apiToken, !token.isEmpty {
            try store.set(token, for: .cdbookingAPIToken(source))
        } else {
            try store.delete(.cdbookingAPIToken(source))
        }
    }

    public func load(for source: SourceID) throws(SecurityError) -> CDBookingCredentials? {
        guard let feedURL = try store.get(.cdbookingFeedURL(source)) else { return nil }
        return CDBookingCredentials(feedURL: feedURL, apiToken: try store.get(.cdbookingAPIToken(source)))
    }

    /// Deletes both secrets (disconnect).
    public func delete(for source: SourceID) throws(SecurityError) {
        try store.delete(.cdbookingFeedURL(source))
        try store.delete(.cdbookingAPIToken(source))
    }
}

/// The cdbooking adapter (BD-15, FR-BOOK-02, Appendix E). Reads the JSON endpoint with `since=`
/// and `If-None-Match`; falls back to the iCal feed when there is no API token or the JSON
/// endpoint is unavailable. `401` and `410` are token revocation and never fall back.
///
/// Endpoints are found from the feed URL's origin, so a move to the native replacement only
/// needs a new feed URL (E.6). Rules only: no model call of any kind (invariant 3).
public struct CDBookingFeedSource: BookingSource {
    public let sourceID: SourceID
    private let secrets: CDBookingSecrets
    private let fetcher: FeedFetcher
    private let timeZone: TimeZone
    private let log = EagarLog(.feeds)

    /// - Parameters:
    ///   - secrets: where the feed URL and API token are kept (the Keychain in the app).
    ///   - fetcher: the HTTP pipeline; tests pass one over the mock cdbooking server.
    ///   - timeZone: for floating and all-day iCal values; cdbooking uses `Europe/Dublin` (E.1).
    public init(
        sourceID: SourceID, secrets: any SecretStore, fetcher: FeedFetcher = FeedFetcher(),
        timeZone: TimeZone = TimeZone(identifier: "Europe/Dublin") ?? .current
    ) {
        self.sourceID = sourceID
        self.secrets = CDBookingSecrets(store: secrets)
        self.fetcher = fetcher
        self.timeZone = timeZone
    }

    /// The feed URL as pasted or scanned, normalised: `webcal://` becomes `https://`; anything
    /// that is not https with a host is refused.
    public static func normalisedFeedURL(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("webcal://") { trimmed = "https://" + trimmed.dropFirst("webcal://".count) }
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https", let host = url.host(), !host.isEmpty else { return nil }
        return url
    }

    /// The JSON endpoints beside a feed URL: the path before `/ical/` is the API base.
    static func endpoints(feedURL: URL) -> (bookings: URL, admin: URL, origin: URL)? {
        guard var components = URLComponents(url: feedURL, resolvingAgainstBaseURL: false) else { return nil }
        let parts = components.path.split(separator: "/", omittingEmptySubsequences: true)
        let prefix = parts.firstIndex(of: "ical").map { parts[..<$0] } ?? []
        let base = prefix.isEmpty ? "" : "/" + prefix.joined(separator: "/")
        components.query = nil
        components.fragment = nil
        components.user = nil
        components.password = nil
        components.path = base
        guard let origin = components.url else { return nil }
        components.path = base + "/api/v1/me/bookings"
        guard let bookings = components.url else { return nil }
        components.path = base + "/api/v1/me/admin-summary"
        guard let admin = components.url else { return nil }
        return (bookings, admin, origin)
    }

    static func bookingsURL(_ base: URL, since: String?) -> URL {
        guard var components = URLComponents(url: base, resolvingAgainstBaseURL: false) else { return base }
        var query: [URLQueryItem] = []
        if let since { query.append(URLQueryItem(name: "since", value: since)) }
        query.append(URLQueryItem(name: "include", value: "items"))
        components.queryItems = query
        // `+` in an RFC 3339 offset would read as a space on the server.
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        return components.url ?? base
    }

    private func credentials() throws(BookingSourceError) -> (feedURL: URL, apiToken: Secret?, endpoints: (bookings: URL, admin: URL, origin: URL)) {
        let loaded: CDBookingCredentials?
        do {
            loaded = try secrets.load(for: sourceID)
        } catch {
            log.error("could not read cdbooking secrets: \(error)")
            throw .notConfigured
        }
        guard let loaded, let url = Self.normalisedFeedURL(loaded.feedURL.reveal()), let endpoints = Self.endpoints(feedURL: url) else {
            throw .notConfigured
        }
        return (url, loaded.apiToken.flatMap { $0.isEmpty ? nil : $0 }, endpoints)
    }

    public func fetchChanges(since cursor: BookingCursor) async throws(BookingSourceError) -> BookingChanges {
        let credentials = try credentials()
        if let token = credentials.apiToken {
            do {
                let url = Self.bookingsURL(credentials.endpoints.bookings, since: cursor.since)
                switch try await fetcher.get(url, bearer: token.reveal(), etag: cursor.etag, accept: "application/json") {
                case .notModified:
                    return .unchanged(cursor: cursor, path: .json)
                case let .modified(body, etag):
                    if let response = CDBookingJSON.decodeBookings(body) {
                        let next = BookingCursor(etag: etag, since: response.nextSince ?? cursor.since, fallbackETag: cursor.fallbackETag)
                        let records = response.bookings.map(\.record)
                        if cursor.since == nil {
                            return .snapshot(bookings: records, cursor: next, path: .json)
                        }
                        return .incremental(upserts: records, deletedIDs: response.deletedIDs ?? [], cursor: next)
                    }
                    log.notice("cdbooking JSON was not cdbooking.bookings.v1; using the iCal feed")
                }
            } catch .unauthorised {
                throw .unauthorised
            } catch .gone {
                throw .revoked
            } catch {
                log.notice("cdbooking JSON unavailable: \(error); using the iCal feed")
            }
        }
        return try await fetchICal(credentials.feedURL, cursor: cursor)
    }

    private func fetchICal(_ url: URL, cursor: BookingCursor) async throws(BookingSourceError) -> BookingChanges {
        let result: FeedFetchResult
        do {
            result = try await fetcher.get(url, etag: cursor.fallbackETag, accept: "text/calendar")
        } catch .unauthorised {
            throw .unauthorised
        } catch .gone {
            throw .revoked
        } catch {
            throw .fetch(error)
        }
        switch result {
        case .notModified:
            return .unchanged(cursor: cursor, path: .iCalendar)
        case let .modified(body, etag):
            let calendar: ICalendar
            do {
                calendar = try ICalendarParser.parse(body, timeZone: timeZone)
            } catch {
                log.notice("cdbooking iCal feed unreadable: \(error)")
                throw .invalidPayload
            }
            var next = cursor
            next.fallbackETag = etag
            return .snapshot(bookings: CDBookingICal.records(from: calendar), cursor: next, path: .iCalendar)
        }
    }

    public func adminSummary() async throws(BookingSourceError) -> AdminSummary? {
        let credentials = try credentials()
        guard let token = credentials.apiToken else { return nil }
        let result: FeedFetchResult
        do {
            result = try await fetcher.get(credentials.endpoints.admin, bearer: token.reveal(), accept: "application/json")
        } catch .unauthorised {
            throw .unauthorised
        } catch .forbidden {
            return nil
        } catch .notFound {
            return nil
        } catch .gone {
            throw .revoked
        } catch {
            throw .fetch(error)
        }
        guard case let .modified(body, _) = result else { return nil }
        guard let admin = CDBookingJSON.decodeAdmin(body) else { throw .invalidPayload }
        let origin = credentials.endpoints.origin
        // The deep link must stay on cdbooking's own host.
        let link = CDBookingJSON.httpsURL(admin.url).flatMap { $0.host() == origin.host() ? $0 : nil }
            ?? origin.appending(path: "admin")
        return AdminSummary(pendingApprovals: admin.pendingApprovals, overdueReturns: admin.overdueReturns, deepLink: link)
    }
}
