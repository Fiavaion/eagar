import EagarCore
import EagarFeeds
import Foundation
import Synchronization

/// An in-process cdbooking server implementing Appendix E (v1), as an ``HTTPTransport``.
///
/// Serves `GET /api/v1/me/bookings?since=&include=items` (bearer auth, `ETag`, `304`,
/// `deleted_ids`, `next_since`), `GET /ical/{feed_token}.ics` (`ETag`, `304`, `TZID=Europe/Dublin`,
/// `DUE`, `X-CDB-STATUS`) and `GET /api/v1/me/admin-summary` (admin scope only). Modes simulate
/// token rotation (401 everywhere), revocation (401 JSON, 410 iCal), a missing JSON endpoint,
/// server errors, rate limiting and malformed or unknown-schema bodies. All data is synthetic.
public final class MockCDBookingServer: HTTPTransport {
    /// A booking as the server stores it.
    public struct Booking: Sendable, Hashable {
        public var id: String
        public var kind: String
        public var status: String
        public var title: String
        public var itemName: String?
        public var location: String?
        public var start: Date
        public var due: Date?
        public var end: Date?
        public var returnedAt: Date?
        public var updatedAt: Date

        public init(
            id: String, kind: String = "equipment", status: String = "checked_out", title: String, itemName: String? = nil,
            location: String? = nil, start: Date, due: Date? = nil, end: Date? = nil, returnedAt: Date? = nil, updatedAt: Date = .distantPast
        ) {
            self.id = id
            self.kind = kind
            self.status = status
            self.title = title
            self.itemName = itemName
            self.location = location
            self.start = start
            self.due = due
            self.end = end
            self.returnedAt = returnedAt
            self.updatedAt = updatedAt
        }
    }

    public enum Mode: Sendable, Equatable {
        case normal
        /// Tokens rotated: `401` from every endpoint (Appendix E.2).
        case tokenRotated
        /// Tokens revoked: `401` from JSON, `410 Gone` from iCal (Appendix E.2).
        case tokenRevoked
        /// The JSON endpoint is not deployed: `404`. iCal still works.
        case jsonUnavailable
        /// The JSON endpoint fails with `500`. iCal still works.
        case jsonServerError
        /// The JSON endpoint answers `429` with `Retry-After`.
        case rateLimited(retryAfter: Int)
        /// The JSON endpoint returns a body that is not JSON.
        case malformedJSON
        /// The JSON endpoint returns a different `schema`.
        case unknownSchema
    }

    /// One request as the server saw it. Records whether a valid token was sent, never the token.
    public struct Request: Sendable, Hashable {
        public let path: String
        public let query: [String: String]
        public let ifNoneMatch: String?
        public let hadValidBearer: Bool
        public let status: Int
    }

    private struct State {
        var bookings: [String: Booking] = [:]
        var deletions: [String: Date] = [:]
        var version = 0
        var mode = Mode.normal
        var adminScope: Bool
        var pendingApprovals = 0
        var overdueReturns = 0
        var requests: [Request] = []
    }

    public let host: String
    public let feedToken: String
    public let apiToken: String
    private let clock: any EagarClock
    private let state: Mutex<State>
    private static let dublin = TimeZone(identifier: "Europe/Dublin")!

    public init(
        host: String = "cdbooking.example", feedToken: String = "synthetic-feed-token-0001",
        apiToken: String = "synthetic-api-token-0001", adminScope: Bool = false, clock: any EagarClock
    ) {
        self.host = host
        self.feedToken = feedToken
        self.apiToken = apiToken
        self.clock = clock
        state = Mutex(State(adminScope: adminScope))
    }

    /// The per-user iCal feed URL (what Mark pastes in FR-BOOK-01).
    public var feedURL: String { "https://\(host)/ical/\(feedToken).ics" }

    // MARK: Control

    /// Adds or replaces a booking, stamping `updatedAt` with the clock.
    public func put(_ booking: Booking) {
        var stamped = booking
        stamped.updatedAt = clock.now()
        state.withLock {
            $0.bookings[stamped.id] = stamped
            $0.deletions[stamped.id] = nil
            $0.version += 1
        }
    }

    /// Removes a booking; it is reported in `deleted_ids` to clients whose `since` is earlier.
    public func remove(id: String) {
        let now = clock.now()
        state.withLock {
            $0.bookings[id] = nil
            $0.deletions[id] = now
            $0.version += 1
        }
    }

    public func setMode(_ mode: Mode) {
        state.withLock { $0.mode = mode }
    }

    public func setAdmin(scope: Bool, pendingApprovals: Int = 0, overdueReturns: Int = 0) {
        state.withLock {
            $0.adminScope = scope
            $0.pendingApprovals = pendingApprovals
            $0.overdueReturns = overdueReturns
        }
    }

    public var requests: [Request] { state.withLock { $0.requests } }

    public func clearRequests() {
        state.withLock { $0.requests.removeAll() }
    }

    // MARK: HTTPTransport

    public func send(_ request: URLRequest) async throws(FeedFetchError) -> HTTPResponse {
        guard let url = request.url, url.host() == host, url.scheme == "https",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { throw .transport }
        var query: [String: String] = [:]
        for item in components.queryItems ?? [] { query[item.name] = item.value ?? "" }
        let bearerOK = request.value(forHTTPHeaderField: "Authorization") == "Bearer \(apiToken)"
        let ifNoneMatch = request.value(forHTTPHeaderField: "If-None-Match")
        let now = clock.now()

        return state.withLock { state in
            let response: HTTPResponse
            switch components.path {
            case "/api/v1/me/bookings":
                response = bookings(state: state, query: query, bearerOK: bearerOK, ifNoneMatch: ifNoneMatch, now: now)
            case "/api/v1/me/admin-summary":
                response = adminSummary(state: state, bearerOK: bearerOK)
            case "/ical/\(feedToken).ics":
                response = iCal(state: state, ifNoneMatch: ifNoneMatch, now: now)
            default:
                response = HTTPResponse(status: 404)
            }
            state.requests.append(Request(path: components.path, query: query, ifNoneMatch: ifNoneMatch, hadValidBearer: bearerOK, status: response.status))
            return response
        }
    }

    private func bookings(state: State, query: [String: String], bearerOK: Bool, ifNoneMatch: String?, now: Date) -> HTTPResponse {
        switch state.mode {
        case .tokenRotated, .tokenRevoked: return HTTPResponse(status: 401)
        case .jsonUnavailable: return HTTPResponse(status: 404)
        case .jsonServerError: return HTTPResponse(status: 500)
        case let .rateLimited(after): return HTTPResponse(status: 429, headers: ["Retry-After": String(after)])
        case .malformedJSON: return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: Data("<html>".utf8))
        case .normal, .unknownSchema: break
        }
        guard bearerOK else { return HTTPResponse(status: 401) }
        let since = query["since"].flatMap(Self.parse)
        if query["since"] != nil, since == nil { return HTTPResponse(status: 400) }
        // The ETag names the user's data version, so a client's last ETag matches until anything changes.
        let etag = "\"j\(state.version)\""
        if ifNoneMatch == etag { return HTTPResponse(status: 304, headers: ["ETag": etag]) }

        let changed = state.bookings.values
            .filter { since == nil || $0.updatedAt > since! }
            .sorted { $0.id < $1.id }
        let deleted = since == nil ? [] : state.deletions.filter { $0.value > since! }.map(\.key).sorted()
        let body: [String: Any] = [
            "schema": state.mode == .unknownSchema ? "cdbooking.bookings.v9" : "cdbooking.bookings.v1",
            "generated_at": Self.format(now, zone: TimeZone(identifier: "UTC")!),
            "user": ["id": "u_synthetic", "display_name": "Synthetic User", "roles": ["staff"]],
            "bookings": changed.map(json),
            "deleted_ids": deleted,
            "next_since": Self.format(now, zone: TimeZone(identifier: "UTC")!),
        ]
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json", "ETag": etag], body: data)
    }

    private func json(_ booking: Booking) -> [String: Any] {
        func time(_ date: Date?) -> Any { date.map { Self.format($0, zone: Self.dublin) } ?? NSNull() }
        var object: [String: Any] = [
            "id": booking.id, "kind": booking.kind, "status": booking.status, "title": booking.title,
            "items": booking.itemName.map { [["id": "i_\(booking.id)", "name": $0, "asset_tag": "CD-0000"]] } ?? [],
            "department": "Synthetic Department", "location": booking.location ?? NSNull(),
            "start": time(booking.start), "due": time(booking.due), "returned_at": time(booking.returnedAt),
            "updated_at": Self.format(booking.updatedAt, zone: TimeZone(identifier: "UTC")!),
            "url": "https://\(host)/bookings/\(booking.id)", "extend_url": "https://\(host)/bookings/\(booking.id)/extend",
        ]
        if booking.kind == "room" { object["end"] = time(booking.end) }
        return object
    }

    private func adminSummary(state: State, bearerOK: Bool) -> HTTPResponse {
        if state.mode == .tokenRotated || state.mode == .tokenRevoked || !bearerOK { return HTTPResponse(status: 401) }
        guard state.adminScope else { return HTTPResponse(status: 403) }
        let body: [String: Any] = [
            "schema": "cdbooking.admin_summary.v1", "pending_approvals": state.pendingApprovals,
            "overdue_returns": state.overdueReturns, "url": "https://\(host)/admin",
        ]
        let data = (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
        return HTTPResponse(status: 200, headers: ["Content-Type": "application/json"], body: data)
    }

    private func iCal(state: State, ifNoneMatch: String?, now: Date) -> HTTPResponse {
        switch state.mode {
        case .tokenRotated: return HTTPResponse(status: 401)
        case .tokenRevoked: return HTTPResponse(status: 410)
        default: break
        }
        let etag = "\"i\(state.version)\""
        if ifNoneMatch == etag { return HTTPResponse(status: 304, headers: ["ETag": etag]) }
        let windowStart = now.addingTimeInterval(-30 * 86400)
        let windowEnd = now.addingTimeInterval(180 * 86400)
        let visible = state.bookings.values
            .filter { $0.start >= windowStart && $0.start <= windowEnd }
            .filter { booking in
                // Cancelled and returned bookings stay for 7 days (E.3).
                guard booking.status == "cancelled" || booking.status == "returned" else { return true }
                return booking.updatedAt > now.addingTimeInterval(-7 * 86400)
            }
            .sorted { $0.id < $1.id }
        var lines = [
            "BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Synthetic//Mock cdbooking//EN", "X-WR-CALNAME:Bookings",
            "BEGIN:VTIMEZONE", "TZID:Europe/Dublin",
            "BEGIN:STANDARD", "DTSTART:19701025T020000", "TZOFFSETFROM:+0100", "TZOFFSETTO:+0000", "END:STANDARD",
            "BEGIN:DAYLIGHT", "DTSTART:19700329T010000", "TZOFFSETFROM:+0000", "TZOFFSETTO:+0100", "END:DAYLIGHT",
            "END:VTIMEZONE",
        ]
        for booking in visible {
            let status = switch booking.status {
            case "requested": "TENTATIVE"
            case "cancelled", "rejected": "CANCELLED"
            default: "CONFIRMED"
            }
            lines += [
                "BEGIN:VEVENT",
                "UID:booking-\(booking.id)@cdbooking.com",
                "DTSTAMP:\(Self.utcStamp(now))",
                "SUMMARY:\(Self.escape(booking.title))",
                "DTSTART;TZID=Europe/Dublin:\(Self.localStamp(booking.start))",
            ]
            if let due = booking.due {
                lines += ["DTEND;TZID=Europe/Dublin:\(Self.localStamp(due))", "DUE;TZID=Europe/Dublin:\(Self.localStamp(due))"]
            } else if let end = booking.end {
                lines.append("DTEND;TZID=Europe/Dublin:\(Self.localStamp(end))")
            }
            if let location = booking.location { lines.append("LOCATION:\(Self.escape(location))") }
            lines += [
                "STATUS:\(status)", "X-CDB-STATUS:\(booking.status)", "X-CDB-KIND:\(booking.kind)",
                "URL:https://\(host)/bookings/\(booking.id)", "LAST-MODIFIED:\(Self.utcStamp(booking.updatedAt))",
                "BEGIN:VALARM", "ACTION:DISPLAY", "DESCRIPTION:Reminder", "TRIGGER:-PT2H", "END:VALARM",
                "END:VEVENT",
            ]
        }
        lines.append("END:VCALENDAR")
        let body = Data((lines.map(Self.fold).joined(separator: "\r\n") + "\r\n").utf8)
        return HTTPResponse(
            status: 200, headers: ["Content-Type": "text/calendar; charset=utf-8", "ETag": etag, "Cache-Control": "private, max-age=300"],
            body: body
        )
    }

    // MARK: Formatting

    /// RFC 3339 with a numeric offset (`+01:00`) or `Z` for UTC.
    static func format(_ date: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let base = String(format: "%04d-%02d-%02dT%02d:%02d:%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
        let offset = zone.secondsFromGMT(for: date)
        if zone.identifier == "UTC" || zone.identifier == "GMT" { return base + "Z" }
        let sign = offset < 0 ? "-" : "+"
        return base + String(format: "%@%02d:%02d", sign, abs(offset) / 3600, abs(offset) % 3600 / 60)
    }

    static func parse(_ text: String) -> Date? {
        try? Date(text, strategy: .iso8601)
    }

    private static func stamp(_ date: Date, zone: TimeZone) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
    }

    static func localStamp(_ date: Date) -> String { stamp(date, zone: dublin) }
    static func utcStamp(_ date: Date) -> String { stamp(date, zone: TimeZone(identifier: "UTC")!) + "Z" }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: ";", with: "\\;")
            .replacingOccurrences(of: ",", with: "\\,").replacingOccurrences(of: "\n", with: "\\n")
    }

    /// Folds lines longer than 75 octets (RFC 5545 §3.1), so clients must unfold.
    static func fold(_ line: String) -> String {
        guard line.utf8.count > 75 else { return line }
        var result = ""
        var current = ""
        for character in line {
            if (current + String(character)).utf8.count > 75 {
                result += current + "\r\n "
                current = ""
            }
            current.append(character)
        }
        return result + current
    }
}
