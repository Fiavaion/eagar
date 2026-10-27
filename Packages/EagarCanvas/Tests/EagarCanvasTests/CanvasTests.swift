import EagarCalendar
import EagarCore
import EagarFeeds
import EagarSecurity
import EagarStore
import EagarSync
import EagarTestSupport
import Foundation
import SwiftData
import Synchronization
import Testing
@testable import EagarCanvas

private func utc(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

private let now = utc(2026, 10, 27, 9)
private let dublin = TimeZone(identifier: "Europe/Dublin")!
private let feedURL = "https://ncad.instructure.com/feeds/calendars/user_SYNTHETICFEEDSECRET0001.ics"

private func fixture() throws -> Data {
    let url = try #require(Bundle.module.url(forResource: "canvas-feed", withExtension: "ics", subdirectory: "Fixtures"))
    return try Data(contentsOf: url)
}

/// Serves the fixture with an ETag; can be switched to an error status.
final class CanvasFeedServer: HTTPTransport {
    private let state: Mutex<(body: Data, status: Int, requests: [URLRequest])>

    init(body: Data) {
        state = Mutex((body, 200, []))
    }

    func setBody(_ body: Data) { state.withLock { $0.body = body } }
    func setStatus(_ status: Int) { state.withLock { $0.status = status } }
    var requests: [URLRequest] { state.withLock { $0.requests } }

    func send(_ request: URLRequest) async throws(FeedFetchError) -> HTTPResponse {
        state.withLock { state in
            state.requests.append(request)
            guard state.status == 200 else { return HTTPResponse(status: state.status) }
            let etag = "\"\(state.body.count)\""
            if request.value(forHTTPHeaderField: "If-None-Match") == etag { return HTTPResponse(status: 304) }
            return HTTPResponse(status: 200, headers: ["ETag": etag], body: state.body)
        }
    }
}

struct CanvasHarness {
    let stores: EagarStores
    let secrets = InMemorySecretStore()
    let sourceID = SourceID()
    let server: CanvasFeedServer

    init() throws {
        stores = try EagarStores(location: .inMemory, models: [CanvasItem.self, FeedSourceRecord.self, Deadline.self])
        server = CanvasFeedServer(body: try fixture())
        try CanvasSecrets(store: secrets).save(feedURL: Secret(feedURL), for: sourceID)
    }

    var importer: CanvasFeedImporter {
        CanvasFeedImporter(
            sourceID: sourceID, secrets: secrets, stores: stores,
            fetcher: FeedFetcher(transport: server, policy: RetryPolicy(maxAttempts: 1), sleep: { _ in }),
            clock: FixedClock(now), timeZone: dublin
        )
    }

    func register() async throws {
        try await FeedSourceRegistry(stores: stores).register(FeedSource.proposed(id: sourceID, kind: .canvas, host: "ncad.instructure.com", profile: .owner), displayName: "Canvas", at: now)
    }

    func deadlines() async throws -> [DeadlineSnapshot] {
        try await stores.college.fetch(FetchDescriptor<Deadline>(sortBy: [SortDescriptor(\.dueAt)])) { $0.snapshot }
    }
}

/// FR-CANVAS-02 mapping and PRD M2 acceptance criterion 4 (fixture `.ics`: assignments,
/// all-day items, time zones).
struct CanvasMappingTests {
    @Test func fixtureMapsToEntries() throws {
        let entries = CanvasMapper.entries(from: try ICalendarParser.parse(try fixture(), timeZone: dublin))
        #expect(entries.map(\.id) == [
            "event-assignment-1001", "event-assignment-1002", "event-assignment-1003",
            "event-calendar-event-2001", "event-calendar-event-2002", "event-calendar-event-2003",
        ])  // the cancelled quiz is dropped
        let byID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

        let essay = try #require(byID["event-assignment-1001"])
        #expect(essay.kind == .assignment && essay.title == "Synthetic essay draft" && essay.courseCode == "SYN101" && essay.courseID == "501")
        #expect(essay.dueAt == utc(2026, 10, 30, 23, 59) && !essay.isAllDay)
        #expect(essay.pageURL?.absoluteString.hasSuffix("#assignment_1001") == true)

        let portfolio = try #require(byID["event-assignment-1002"])
        #expect(portfolio.isAllDay && portfolio.dueAt == utc(2026, 11, 6) && portfolio.courseID == "502")

        // 17:00 in New York on 5 Nov (EST, UTC−5) is 22:00 UTC.
        #expect(byID["event-assignment-1003"]?.dueAt == utc(2026, 11, 5, 22))

        let visit = try #require(byID["event-calendar-event-2001"])
        #expect(visit.kind == .event && visit.dueAt == nil && visit.start == utc(2026, 10, 29, 14) && visit.end == utc(2026, 10, 29, 15, 30))
        #expect(byID["event-calendar-event-2002"]?.isAllDay == true && byID["event-calendar-event-2002"]?.courseCode == nil)
        // 09:00 in Tokyo (UTC+9) is midnight UTC.
        #expect(byID["event-calendar-event-2003"]?.start == utc(2026, 11, 10, 0))
    }

    static let summaryCases: [(String, String, String?)] = [
        ("Essay [SYN101]", "Essay", "SYN101"),
        ("Essay [part 1] [SYN101]", "Essay [part 1]", "SYN101"),
        ("Reading week", "Reading week", nil),
        ("[SYN101]", "[SYN101]", nil),
        ("Essay []", "Essay []", nil),
    ]

    @Test(arguments: summaryCases)
    func splitsCourseCodes(_ c: (String, String, String?)) {
        let split = CanvasMapper.splitCourse(c.0)
        #expect(split.title == c.1 && split.courseCode == c.2)
    }

    @Test func linkHeuristicsDecideKindWhenUIDIsOpaque() throws {
        let text = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:abc\nDTSTART:20261101T100000Z\nURL:https://x.instructure.com/courses/7/assignments/9\nEND:VEVENT\nBEGIN:VEVENT\nUID:def\nDTSTART:20261101T100000Z\nEND:VEVENT\nEND:VCALENDAR\n"
        let entries = CanvasMapper.entries(from: try ICalendarParser.parse(text, timeZone: dublin))
        #expect(entries.map(\.kind) == [.assignment, .event])
        #expect(entries.first?.courseID == "7")
    }

    @Test func normalisesFeedURLs() {
        #expect(CanvasFeedImporter.normalisedFeedURL("webcal://ncad.instructure.com/feeds/x.ics")?.scheme == "https")
        #expect(CanvasFeedImporter.normalisedFeedURL("http://ncad.instructure.com/feeds/x.ics") == nil)
    }
}

struct CanvasImportTests {
    @Test func importProducesDeadlinesForAssignmentsOnly() async throws {
        let h = try CanvasHarness()
        try await h.register()
        let outcome = try await h.importer.refresh()
        #expect(outcome.changed && outcome.entries == 6 && outcome.deadlines.inserted == 3)

        let deadlines = try await h.deadlines()
        #expect(deadlines.map(\.title) == ["Synthetic essay draft (SYN101)", "Synthetic reading response (SYN101)", "Synthetic portfolio review (SYN202)"])
        #expect(deadlines.allSatisfy { $0.origin == .canvas && $0.dataClass == .college && $0.status == .open })
        #expect(deadlines.map(\.dueAt) == [utc(2026, 10, 30, 23, 59), utc(2026, 11, 5, 22), utc(2026, 11, 6)])
        #expect(deadlines.map(\.isAllDay) == [false, false, true])
        #expect(try await CanvasRepository(stores: h.stores).all().count == 6)

        let state = try #require(try await FeedSourceRegistry(stores: h.stores).state(of: h.sourceID))
        #expect(state.health == .ok && state.etag != nil)
    }

    @Test func unchangedFeedIs304AndRemovedItemsDisappear() async throws {
        let h = try CanvasHarness()
        try await h.register()
        try await h.importer.refresh()
        #expect(try await h.importer.refresh().changed == false)
        #expect(h.server.requests.last?.value(forHTTPHeaderField: "If-None-Match") != nil)

        // The essay leaves the feed.
        var text = String(decoding: try fixture(), as: UTF8.self)
        let start = try #require(text.range(of: "BEGIN:VEVENT\nDTEND:20261030T235900Z"))
        let end = try #require(text.range(of: "END:VEVENT\n", range: start.upperBound ..< text.endIndex))
        text.removeSubrange(start.lowerBound ..< end.upperBound)
        h.server.setBody(Data(text.utf8))
        let outcome = try await h.importer.refresh()
        #expect(outcome.deleted == 1 && outcome.deadlines.deleted == 1)
        #expect(try await h.deadlines().count == 2)
    }

    @Test func eventsOnlyWhenAssignmentDeadlinesAreOff() async throws {
        let h = try CanvasHarness()
        try await h.register()
        let importer = CanvasFeedImporter(
            sourceID: h.sourceID, secrets: h.secrets, stores: h.stores,
            fetcher: FeedFetcher(transport: h.server, policy: RetryPolicy(maxAttempts: 1), sleep: { _ in }),
            clock: FixedClock(now), timeZone: dublin, assignmentsAsDeadlines: false
        )
        try await importer.refresh()
        #expect(try await h.deadlines().isEmpty)
    }

    @Test(arguments: [(401, CanvasImportError.unauthorised, FeedHealth.unauthorised), (404, .revoked, .revoked), (410, .revoked, .revoked), (500, .fetch(.server(status: 500)), .failing)])
    func failuresAreTypedAndRecorded(_ c: (status: Int, error: CanvasImportError, health: FeedHealth)) async throws {
        let h = try CanvasHarness()
        try await h.register()
        h.server.setStatus(c.status)
        await #expect(throws: c.error) { try await h.importer.refresh() }
        #expect(try await FeedSourceRegistry(stores: h.stores).state(of: h.sourceID)?.health == c.health)
    }

    @Test func truncatedFeedChangesNothing() async throws {
        let h = try CanvasHarness()
        try await h.register()
        try await h.importer.refresh()
        h.server.setBody(Data("BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:x\nDTSTART:20261101T100000Z\nEND:VEVENT\n".utf8))
        await #expect(throws: CanvasImportError.invalidPayload) { try await h.importer.refresh() }
        #expect(try await h.deadlines().count == 3)
    }

    @Test func missingURLIsNotConfigured() async throws {
        let h = try CanvasHarness()
        try await h.register()
        try CanvasSecrets(store: h.secrets).delete(for: h.sourceID)
        await #expect(throws: CanvasImportError.notConfigured) { try await h.importer.refresh() }
        #expect(h.server.requests.isEmpty)
    }

    @Test func disconnectRemovesEverything() async throws {
        let h = try CanvasHarness()
        try await h.register()
        try await h.importer.refresh()
        try await h.importer.disconnect()
        #expect(try await CanvasRepository(stores: h.stores).all().isEmpty)
        #expect(try await h.deadlines().isEmpty)
        #expect(try h.secrets.get(.canvasFeedURL(h.sourceID)) == nil)
        #expect(try await FeedSourceRegistry(stores: h.stores).state(of: h.sourceID) == nil)
    }
}

final class CanvasLogCapture: LogSink {
    private let records = Mutex<[String]>([])
    func receive(_ record: LogRecord) { records.withLock { $0.append(record.text) } }
    var texts: [String] { records.withLock { $0 } }
}

/// B-8 (package level) for Canvas.
struct CanvasBoundaryTests {
    @Test func Boundary_B8_canvasRecordsAreCollegeAndCollegeStoreOnly() async throws {
        let h = try CanvasHarness()
        let source = h.sourceID
        #expect(CanvasItem(CanvasEntry(id: "u", kind: .event, title: "t"), source: source, fetchedAt: now).dataClass == .college)
        await #expect(throws: StoreError.classMismatch(store: .personal, dataClass: .college)) {
            try await h.stores.personal.insert(CanvasItem(CanvasEntry(id: "u", kind: .event, title: "t"), source: source, fetchedAt: now))
        }
        try await h.register()
        try await h.importer.refresh()
        #expect(try await h.stores.personal.fetch(FetchDescriptor<CanvasItem>()) { $0.uid }.isEmpty)
        #expect(try await h.stores.personal.fetch(FetchDescriptor<Deadline>()) { $0.title }.isEmpty)
        #expect(try await h.stores.personal.fetch(FetchDescriptor<FeedSourceRecord>()) { $0.displayName }.isEmpty)
        #expect(try await h.stores.college.fetch(FetchDescriptor<CanvasItem>()) { $0.dataClass }.allSatisfy { $0 == .college })
    }

    @Test func Boundary_B8_collegeStoreCannotBeSynced() throws {
        let h = try CanvasHarness()
        #expect(throws: StoreError.syncForbidden(.college)) { try SyncRegistry.register(h.stores.college, engine: "spy") }
        #expect(throws: StoreError.syncForbidden(.college)) {
            _ = try SyncCoordinator(store: h.stores.college, adapters: [AnySyncAdapter(DeadlineSyncAdapter())], stateURL: nil)
        }
    }

    /// M2 acceptance: the Canvas feed URL is in the secret store and in no persisted record.
    @Test func Boundary_B8_feedURLInKeychainNotSwiftData() async throws {
        let h = try CanvasHarness()
        try await h.register()
        try await h.importer.refresh()
        #expect(try h.secrets.get(.canvasFeedURL(h.sourceID))?.reveal() == feedURL)
        var stored: [String] = []
        stored += try await h.stores.college.fetch(FetchDescriptor<CanvasItem>()) {
            [$0.uid, $0.kindRaw, $0.title, $0.courseCode ?? "", $0.courseID ?? "", $0.pageURL ?? "", $0.dataClassRaw]
        }.flatMap { $0 }
        stored += try await h.stores.college.fetch(FetchDescriptor<FeedSourceRecord>()) {
            [$0.displayName, $0.etag ?? "", $0.cursor ?? "", $0.fallbackETag ?? "", $0.kindRaw]
        }.flatMap { $0 }
        stored += try await h.stores.college.fetch(FetchDescriptor<Deadline>()) { [$0.title] }.flatMap { $0 }
        #expect(!stored.isEmpty)
        for value in stored {
            #expect(!value.contains("SYNTHETICFEEDSECRET0001") && !value.contains("/feeds/calendars/"), "\(value)")
        }
    }

    @Test func Boundary_B8_logsCarryNoContentOrSecrets() async throws {
        let capture = CanvasLogCapture()
        let token = EagarLog.addSink(capture)
        defer { EagarLog.removeSink(token) }
        let h = try CanvasHarness()
        try await h.register()
        try await h.importer.refresh()
        h.server.setStatus(401)
        _ = try? await h.importer.refresh()
        #expect(capture.texts.contains { $0.contains("canvas refresh") })
        for text in capture.texts {
            for word in ["SYNTHETICFEEDSECRET0001", "instructure", "Synthetic", "SYN101", "event-assignment"] {
                #expect(!text.contains(word), "\(text)")
            }
        }
    }
}
