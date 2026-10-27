import EagarCore
import EagarFeeds
import Foundation

/// Where a source left off: ETags and the incremental cursor. Content-free.
public struct BookingCursor: Sendable, Hashable {
    /// `ETag` of the JSON endpoint for `since`.
    public var etag: String?
    /// cdbooking `next_since` (RFC 3339), sent back as `since=`.
    public var since: String?
    /// `ETag` of the iCal feed (fallback path).
    public var fallbackETag: String?

    public init(etag: String? = nil, since: String? = nil, fallbackETag: String? = nil) {
        self.etag = etag
        self.since = since
        self.fallbackETag = fallbackETag
    }
}

/// Which endpoint answered.
public enum BookingFetchPath: String, Sendable, Hashable, LogSafe {
    /// The JSON endpoint (Appendix E.4).
    case json
    /// The iCal feed, used when JSON is unavailable (FR-BOOK-02).
    case iCalendar

    public var logDescription: String { rawValue }
}

/// What changed since the cursor.
public enum BookingChanges: Sendable, Hashable {
    /// `304 Not Modified`.
    case unchanged(cursor: BookingCursor, path: BookingFetchPath)
    /// Changes since `since`: upserts and deletions only.
    case incremental(upserts: [BookingRecord], deletedIDs: [String], cursor: BookingCursor)
    /// Every current booking; anything not listed is gone.
    case snapshot(bookings: [BookingRecord], cursor: BookingCursor, path: BookingFetchPath)
}

/// Content-free counts for an admin (FR-BOOK-06). No names, no booking details.
public struct AdminSummary: Sendable, Hashable, Classified {
    public let pendingApprovals: Int
    public let overdueReturns: Int
    /// The admin page on cdbooking.
    public let deepLink: URL

    public init(pendingApprovals: Int, overdueReturns: Int, deepLink: URL) {
        self.pendingApprovals = max(0, pendingApprovals)
        self.overdueReturns = max(0, overdueReturns)
        self.deepLink = deepLink
    }

    /// Derived from college data, so college; but counts only, which BD-04 allows in
    /// notifications and widgets.
    public var dataClass: DataClass { .college }
    public var sourceID: SourceID? { nil }
}

/// Errors from a booking source. Content-free.
public enum BookingSourceError: Error, Equatable, Sendable, LogSafe {
    /// The feed URL is missing from the Keychain (or malformed).
    case notConfigured
    /// `401`: the token was rotated or revoked; Mark must paste a new one (Appendix E.2).
    case unauthorised
    /// `410 Gone`: the iCal feed was revoked (Appendix E.2).
    case revoked
    /// A network or server failure, after retries.
    case fetch(FeedFetchError)
    /// The body could not be read as either format.
    case invalidPayload

    public var logDescription: String {
        switch self {
        case .notConfigured: "notConfigured"
        case .unauthorised: "unauthorised"
        case .revoked: "revoked"
        case let .fetch(error): "fetch(\(error.logDescription))"
        case .invalidPayload: "invalidPayload"
        }
    }

    /// The feed health this error leaves the source in.
    public var health: FeedHealth {
        switch self {
        case .notConfigured: .notConfigured
        case .unauthorised: .unauthorised
        case .revoked: .revoked
        case .fetch, .invalidPayload: .failing
        }
    }
}

/// A source of bookings (FR-BOOK-08). Consumers (``BookingSync``, the app) depend only on this,
/// so the native replacement can be added as a second adapter with no change to them.
public protocol BookingSource: Sendable {
    var sourceID: SourceID { get }
    /// Bookings changed since `cursor`.
    func fetchChanges(since cursor: BookingCursor) async throws(BookingSourceError) -> BookingChanges
    /// Admin counts, or nil when the token has no admin scope or the server has no summary.
    func adminSummary() async throws(BookingSourceError) -> AdminSummary?
}
