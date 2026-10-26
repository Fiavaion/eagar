import EagarCore
import EagarFeeds
import EagarSecurity
import EagarTestSupport
import Foundation
import Testing
@testable import EagarBookings

/// FR-BOOK-01/02/06/08 against the mock cdbooking server (PRD M2 acceptance criterion 1).
struct CDBookingFeedSourceTests {
    @Test func jsonSnapshotThenNotModifiedThenIncremental() async throws {
        let h = try BookingHarness()
        h.seed()

        guard case let .snapshot(bookings, cursor, path) = try await h.source.fetchChanges(since: BookingCursor()) else {
            Issue.record("expected a snapshot"); return
        }
        #expect(path == .json)
        #expect(bookings.count == 4)
        let kit = try #require(bookings.first { $0.id == "b_789" })
        #expect(kit.kind == .equipment)
        #expect(kit.status == .checkedOut)
        #expect(kit.title == "Synthetic camera kit")
        #expect(kit.itemNames == ["Synthetic camera body"])
        #expect(kit.due == utcDate(2026, 10, 28, 16))
        #expect(kit.start == utcDate(2026, 10, 26, 10))   // written with a +00:00 / +01:00 offset
        #expect(kit.extendURL?.absoluteString == "https://cdbooking.example/bookings/b_789/extend")
        #expect(kit.isActiveLoan)
        let room = try #require(bookings.first { $0.id == "b_790" })
        #expect(room.kind == .room && room.end == utcDate(2026, 10, 28, 12) && room.due == nil && !room.isActiveLoan)
        #expect(bookings.first { $0.id == "b_792" }?.isClosed == true)
        #expect(cursor.since == "2026-10-27T09:00:00Z")
        #expect(cursor.etag != nil)

        let first = try #require(h.server.requests.last)
        #expect(first.path == "/api/v1/me/bookings" && first.hadValidBearer && first.query["include"] == "items" && first.query["since"] == nil)

        // Same cursor: 304.
        guard case .unchanged(_, .json) = try await h.source.fetchChanges(since: cursor) else { Issue.record("expected 304"); return }
        #expect(h.server.requests.last?.ifNoneMatch == cursor.etag)
        #expect(h.server.requests.last?.status == 304)
        #expect(h.server.requests.last?.query["since"] == "2026-10-27T09:00:00Z")

        // A change and a deletion after the cursor arrive incrementally.
        h.clock.advance(by: 600)
        var returned = MockCDBookingServer.Booking(id: "b_789", status: "returned", title: "Synthetic camera kit", start: utcDate(2026, 10, 26, 10),
                                                   due: utcDate(2026, 10, 28, 16), returnedAt: fixtureNow.addingTimeInterval(600))
        returned.location = "Returns desk"
        h.server.put(returned)
        h.server.remove(id: "b_791")
        guard case let .incremental(upserts, deleted, next) = try await h.source.fetchChanges(since: cursor) else {
            Issue.record("expected incremental"); return
        }
        #expect(upserts.map(\.id) == ["b_789"])
        #expect(upserts.first?.isClosed == true)
        #expect(deleted == ["b_791"])
        #expect(next.since == "2026-10-27T09:10:00Z")
    }

    @Test(arguments: [MockCDBookingServer.Mode.jsonUnavailable, .jsonServerError, .malformedJSON, .unknownSchema, .rateLimited(retryAfter: 1)])
    func fallsBackToICalWhenJSONIsUnavailable(_ mode: MockCDBookingServer.Mode) async throws {
        let h = try BookingHarness()
        h.seed()
        h.server.setMode(mode)
        guard case let .snapshot(bookings, cursor, path) = try await h.source.fetchChanges(since: BookingCursor()) else {
            Issue.record("expected a snapshot"); return
        }
        #expect(path == .iCalendar)
        #expect(Set(bookings.map(\.id)) == ["b_789", "b_790", "b_791", "b_792"])
        let kit = try #require(bookings.first { $0.id == "b_789" })
        #expect(kit.due == utcDate(2026, 10, 28, 16))
        #expect(kit.status == .checkedOut)
        #expect(kit.location == "Returns desk")
        #expect(kit.isActiveLoan)
        let room = try #require(bookings.first { $0.id == "b_790" })
        #expect(room.kind == .room && room.due == nil)
        #expect(bookings.first { $0.id == "b_791" }?.status == .requested)
        #expect(cursor.fallbackETag != nil)
        #expect(cursor.since == nil)

        // The iCal feed answers 304 for the same ETag.
        guard case .unchanged(_, .iCalendar) = try await h.source.fetchChanges(since: cursor) else { Issue.record("expected 304"); return }
    }

    @Test func iCalOnlyWithoutAnAPIToken() async throws {
        let h = try BookingHarness(withAPIToken: false)
        h.seed()
        guard case let .snapshot(bookings, _, .iCalendar) = try await h.source.fetchChanges(since: BookingCursor()) else {
            Issue.record("expected an iCal snapshot"); return
        }
        #expect(bookings.count == 4)
        #expect(h.server.requests.allSatisfy { $0.path.hasPrefix("/ical/") })
        #expect(try await h.source.adminSummary() == nil)
    }

    @Test func rotatedTokenIsUnauthorisedWithoutFallback() async throws {
        let h = try BookingHarness()
        h.server.setMode(.tokenRotated)
        await #expect(throws: BookingSourceError.unauthorised) { try await h.source.fetchChanges(since: BookingCursor()) }
        #expect(h.server.requests.count == 1)
        #expect(BookingSourceError.unauthorised.health == .unauthorised)
    }

    @Test func revokedTokenIsUnauthorisedOnJSONAndGoneOnICal() async throws {
        let h = try BookingHarness()
        h.server.setMode(.tokenRevoked)
        await #expect(throws: BookingSourceError.unauthorised) { try await h.source.fetchChanges(since: BookingCursor()) }
        #expect(!h.server.requests.contains { $0.path.hasPrefix("/ical/") })

        let icalOnly = try BookingHarness(withAPIToken: false)
        icalOnly.server.setMode(.tokenRevoked)
        await #expect(throws: BookingSourceError.revoked) { try await icalOnly.source.fetchChanges(since: BookingCursor()) }
        #expect(BookingSourceError.revoked.health == .revoked)
    }

    @Test func missingSecretsAreNotConfigured() async throws {
        let h = try BookingHarness()
        try CDBookingSecrets(store: h.secrets).delete(for: h.sourceID)
        await #expect(throws: BookingSourceError.notConfigured) { try await h.source.fetchChanges(since: BookingCursor()) }
        #expect(h.server.requests.isEmpty)
    }

    @Test func adminSummaryIsCountsOnlyAndNeedsScope() async throws {
        let h = try BookingHarness()
        #expect(try await h.source.adminSummary() == nil)
        h.server.setAdmin(scope: true, pendingApprovals: 4, overdueReturns: 2)
        let summary = try #require(try await h.source.adminSummary())
        #expect(summary.pendingApprovals == 4)
        #expect(summary.overdueReturns == 2)
        #expect(summary.deepLink.absoluteString == "https://cdbooking.example/admin")
        #expect(summary.dataClass == .college)
    }

    // MARK: URLs

    static let feedURLCases: [(String, String?)] = [
        ("https://cdbooking.com/ical/abc.ics", "https://cdbooking.com/ical/abc.ics"),
        ("  webcal://cdbooking.com/ical/abc.ics\n", "https://cdbooking.com/ical/abc.ics"),
        ("http://cdbooking.com/ical/abc.ics", nil),
        ("cdbooking.com/ical/abc.ics", nil),
        ("not a url", nil),
    ]

    @Test(arguments: feedURLCases)
    func normalisesFeedURLs(_ c: (String, String?)) {
        #expect(CDBookingFeedSource.normalisedFeedURL(c.0)?.absoluteString == c.1)
    }

    static let endpointCases: [(String, String, String)] = [
        ("https://cdbooking.com/ical/abc.ics", "https://cdbooking.com/api/v1/me/bookings", "https://cdbooking.com/api/v1/me/admin-summary"),
        ("https://relay.example.org/cdb/ical/abc.ics?x=1", "https://relay.example.org/cdb/api/v1/me/bookings", "https://relay.example.org/cdb/api/v1/me/admin-summary"),
        ("https://cdbooking.com:8443/feed.ics", "https://cdbooking.com:8443/api/v1/me/bookings", "https://cdbooking.com:8443/api/v1/me/admin-summary"),
    ]

    @Test(arguments: endpointCases)
    func derivesJSONEndpointsFromTheFeedURL(_ c: (String, String, String)) throws {
        let endpoints = try #require(CDBookingFeedSource.endpoints(feedURL: URL(string: c.0)!))
        #expect(endpoints.bookings.absoluteString == c.1)
        #expect(endpoints.admin.absoluteString == c.2)
    }

    @Test func sinceWithAnOffsetIsPercentEncoded() {
        let url = CDBookingFeedSource.bookingsURL(URL(string: "https://cdbooking.com/api/v1/me/bookings")!, since: "2026-10-25T10:00:00+01:00")
        #expect(url.absoluteString == "https://cdbooking.com/api/v1/me/bookings?since=2026-10-25T10:00:00%2B01:00&include=items")
    }

    @Test func iCalUIDsMapToBookingIDs() {
        #expect(CDBookingICal.bookingID(fromUID: "booking-b_789@cdbooking.com") == "b_789")
        #expect(CDBookingICal.bookingID(fromUID: "other-uid") == "other-uid")
    }

    @Test func unknownStatusesAreTolerated() {
        #expect(BookingStatus(wire: "CHECKED_OUT") == .checkedOut)
        #expect(BookingStatus(wire: "lost_in_transit") == .unknown)
    }
}
