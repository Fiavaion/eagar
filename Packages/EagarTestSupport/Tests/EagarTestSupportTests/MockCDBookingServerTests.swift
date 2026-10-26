import EagarFeeds
import Foundation
import Testing
@testable import EagarTestSupport

/// The mock follows Appendix E: bearer auth, ETag/304, `since`, iCal, revocation modes.
struct MockCDBookingServerTests {
    let clock = FixedClock(Date(timeIntervalSince1970: 1_793_000_000))

    func get(_ server: MockCDBookingServer, _ path: String, bearer: String? = nil, etag: String? = nil) async throws -> HTTPResponse {
        var request = URLRequest(url: URL(string: "https://\(server.host)\(path)")!)
        if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        return try await server.send(request)
    }

    @Test func jsonNeedsTheTokenAndHonoursETag() async throws {
        let server = MockCDBookingServer(clock: clock)
        server.put(.init(id: "b_1", title: "Synthetic", start: clock.now(), due: clock.now().addingTimeInterval(3600)))
        #expect(try await get(server, "/api/v1/me/bookings").status == 401)
        let ok = try await get(server, "/api/v1/me/bookings", bearer: server.apiToken)
        #expect(ok.status == 200)
        let etag = try #require(ok.header("etag"))
        #expect(try await get(server, "/api/v1/me/bookings", bearer: server.apiToken, etag: etag).status == 304)
        let body = try #require(try JSONSerialization.jsonObject(with: ok.body) as? [String: Any])
        #expect(body["schema"] as? String == "cdbooking.bookings.v1")
        #expect((body["bookings"] as? [Any])?.count == 1)
    }

    @Test func iCalAndRevocationModes() async throws {
        let server = MockCDBookingServer(clock: clock)
        server.put(.init(id: "b_1", title: "Synthetic", start: clock.now(), due: clock.now().addingTimeInterval(3600)))
        let ical = try await get(server, "/ical/\(server.feedToken).ics")
        #expect(ical.status == 200)
        #expect(String(decoding: ical.body, as: UTF8.self).contains("UID:booking-b_1@cdbooking.com"))
        #expect(try await get(server, "/ical/wrong-token.ics").status == 404)
        server.setMode(.tokenRevoked)
        #expect(try await get(server, "/ical/\(server.feedToken).ics").status == 410)
        #expect(try await get(server, "/api/v1/me/bookings", bearer: server.apiToken).status == 401)
        #expect(server.requests.allSatisfy { $0.path != "" })
    }
}
