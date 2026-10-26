import EagarBookings
import EagarCalendar
import EagarCore
import EagarFeeds
import EagarSecurity
import EagarStore
import EagarTestSupport
import Foundation
import Synchronization

/// Tuesday 27 October 2026, 09:00 in Dublin (UTC+0 after the clocks went back on the 25th).
let fixtureNow: Date = utcDate(2026, 10, 27, 9)

func utcDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

let dublinCalendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
    return calendar
}()

/// Records retry delays without waiting.
final class NoSleep: Sendable {
    private let delays = Mutex<[Duration]>([])
    var all: [Duration] { delays.withLock { $0 } }
    var sleeper: FeedFetcher.Sleeper { { [self] d in delays.withLock { $0.append(d) } } }
}

/// A mock server, secret store, stores and a source wired together.
struct BookingHarness {
    let clock = FixedClock(fixtureNow)
    let server: MockCDBookingServer
    let secrets = InMemorySecretStore()
    let stores: EagarStores
    let sourceID = SourceID()
    let sleeps = NoSleep()

    init(adminScope: Bool = false, withAPIToken: Bool = true) throws {
        server = MockCDBookingServer(adminScope: adminScope, clock: clock)
        stores = try EagarStores(location: .inMemory, models: [BookingItem.self, FeedSourceRecord.self, Deadline.self])
        try CDBookingSecrets(store: secrets).save(
            CDBookingCredentials(feedURL: Secret(server.feedURL), apiToken: withAPIToken ? Secret(server.apiToken) : nil), for: sourceID
        )
    }

    var source: CDBookingFeedSource {
        CDBookingFeedSource(
            sourceID: sourceID, secrets: secrets,
            fetcher: FeedFetcher(transport: server, policy: RetryPolicy(maxAttempts: 2), sleep: sleeps.sleeper)
        )
    }

    var sync: BookingSync { BookingSync(stores: stores, clock: clock) }

    func register() async throws {
        try await FeedSourceRegistry(stores: stores).register(
            FeedSource.proposed(id: sourceID, kind: .cdbooking, host: server.host, profile: .owner), displayName: "Bookings", at: fixtureNow
        )
    }

    /// A camera kit out until tomorrow 16:00, a room tomorrow, a pending request and a returned tripod.
    func seed() {
        server.put(.init(id: "b_789", title: "Synthetic camera kit", itemName: "Synthetic camera body", location: "Returns desk",
                         start: utcDate(2026, 10, 26, 10), due: utcDate(2026, 10, 28, 16)))
        server.put(.init(id: "b_790", kind: "room", status: "approved", title: "Synthetic studio room", location: "Studio 2",
                         start: utcDate(2026, 10, 28, 10), end: utcDate(2026, 10, 28, 12)))
        server.put(.init(id: "b_791", status: "requested", title: "Synthetic tripod request", start: utcDate(2026, 10, 30, 10), due: utcDate(2026, 11, 2, 16)))
        server.put(.init(id: "b_792", status: "returned", title: "Synthetic light kit", start: utcDate(2026, 10, 20, 10),
                         due: utcDate(2026, 10, 22, 16), returnedAt: utcDate(2026, 10, 22, 15)))
    }
}

/// Collects log records for content checks.
final class LogCapture: LogSink {
    private let records = Mutex<[LogRecord]>([])
    func receive(_ record: LogRecord) { records.withLock { $0.append(record) } }
    var texts: [String] { records.withLock { $0.map(\.text) } }
}
