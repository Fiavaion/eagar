import CloudKit
import EagarAI
import EagarBookings
import EagarBrief
import EagarCalendar
import EagarCanvas
import EagarCore
import EagarFeeds
import EagarSecurity
import EagarStore
import EagarSync
import Foundation
import SwiftData
import Synchronization
import Testing
@testable import Eagar

/// Records every routed call and answers "ok". Local stand-in for EagarTestSupport's
/// RecordingProvider, which the app tests deliberately don't link (see `MemorySecrets`).
private final class SpyProvider: LLMProvider {
    struct Call: Sendable {
        let tier: Tier
        let wire: String
        let payloads: [ClassifiedPayload]
    }

    let id: ProviderID
    let locality: DataLocality
    private let calls = Mutex<[Call]>([])

    init(_ locality: DataLocality) {
        self.locality = locality
        id = ProviderID("spy.\(locality.tier.rawValue)")
    }

    var recorded: [Call] { calls.withLock { $0 } }

    func capabilities() async -> ProviderCapabilities {
        ProviderCapabilities(locality: locality, defaultModel: ModelID("claude-haiku-5-5"), maxContextTokens: 100_000)
    }

    func reachability() async -> Reachability { .reachable }

    func encodeRequest(_ request: AIRequest, model: ModelID) throws(AIError) -> Data? {
        guard locality.tier.leavesOwnerDevices else { return nil }
        return Data(([model.rawValue] + request.allPayloads.map(\.text)).joined(separator: "\n").utf8)
    }

    func complete(_ call: RoutedCall) async throws(AIError) -> LLMResponse {
        let wire = String(decoding: call.wirePayload ?? Data(), as: UTF8.self)
        calls.withLock { $0.append(Call(tier: call.tier, wire: wire, payloads: call.request.allPayloads)) }
        return LLMResponse(text: "ok", model: call.model, usage: LLMUsage(inputTokens: 10, outputTokens: 2))
    }
}

/// Synthetic cdbooking (JSON with a bearer token, admin summary, iCal) and Canvas feeds, timed
/// relative to the test clock. Never touches the network.
private final class StubFeeds: HTTPTransport {
    static let feedToken = "feed-canary-7f3a9c"
    static let apiToken = "api-canary-91d2e4"
    static let feedURL = "https://cdbooking.example.invalid/ical/\(feedToken).ics"
    static let canvasURL = "https://canvas.example.invalid/feeds/calendars/user_canary-5b8e.ics"

    let now: Date
    let calendar: Calendar
    let revoked = Mutex(false)

    init(now: Date, calendar: Calendar) {
        self.now = now
        self.calendar = calendar
    }

    func send(_ request: URLRequest) async throws(FeedFetchError) -> HTTPResponse {
        guard let url = request.url else { return HTTPResponse(status: 400) }
        if url.host() == "canvas.example.invalid" {
            return HTTPResponse(status: 200, body: Data(DemoFeedTransport.canvasFeed(now: now, calendar: calendar).utf8))
        }
        guard url.host() == "cdbooking.example.invalid" else { return HTTPResponse(status: 404) }
        if revoked.withLock({ $0 }) { return HTTPResponse(status: 401) }
        let path = url.path()
        if path.contains("/ical/") {
            return HTTPResponse(status: 200, body: Data(DemoFeedTransport.cdbookingFeed(now: now, calendar: calendar).utf8))
        }
        guard request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.apiToken)" else { return HTTPResponse(status: 401) }
        if path.hasSuffix("/admin-summary") {
            let json = #"{"schema":"cdbooking.admin_summary.v1","pending_approvals":3,"overdue_returns":1,"url":"https://cdbooking.example.invalid/admin"}"#
            return HTTPResponse(status: 200, body: Data(json.utf8))
        }
        let iso = Date.ISO8601FormatStyle()
        let due = (calendar.date(bySettingHour: 17, minute: 0, second: 0, of: now) ?? now).formatted(iso)
        let json = """
        {"schema":"cdbooking.bookings.v1","next_since":"\(now.formatted(iso))","bookings":[
          {"id":"b_canary","kind":"equipment","status":"checked_out","title":"Canary camera kit",
           "items":[{"name":"Canary camera kit"}],"location":"Canary loans desk","due":"\(due)",
           "url":"https://cdbooking.example.invalid/bookings/b_canary","extend_url":"https://cdbooking.example.invalid/bookings/b_canary/extend"}
        ]}
        """
        return HTTPResponse(status: 200, headers: ["ETag": "\"v1\""], body: Data(json.utf8))
    }
}

/// Records planned deadline notifications.
private final class SpyDeadlineScheduler: NotificationScheduling {
    let added = Mutex<[PlannedNotification]>([])
    func pendingIdentifiers() async -> [String] { added.withLock { $0.map(\.id) } }
    /// Replaces by identifier, as `UNUserNotificationCenter` does.
    func add(_ planned: PlannedNotification) async throws {
        added.withLock { list in
            list.removeAll { $0.id == planned.id }
            list.append(planned)
        }
    }
    func remove(identifiers: [String]) async { added.withLock { $0.removeAll { identifiers.contains($0.id) } } }
    func requestAuthorization() async throws -> Bool { true }
}

/// Fetches from a store off the main actor with a sendable mapping.
private func rows<T: PersistentModel, R: Sendable>(_ store: ClassifiedStore, _: T.Type, _ map: @escaping @Sendable (T) -> R) async throws -> [R] {
    try await store.fetch(FetchDescriptor<T>(), map: map)
}

private struct FixedTestClock: EagarClock {
    let date: Date
    func now() -> Date { date }
}

/// M2 acceptance: B-8 end to end through the app (cdbooking and Canvas records are college,
/// CollegeStore-only, never in the sync engine, never in a cloud AI payload), feed secrets in
/// the Keychain, return reminders, clash proposals and feed health.
@MainActor
struct FeedBoundaryTests {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        return calendar
    }()
    /// Tuesday 27 October 2026, 07:00 in Dublin.
    private var morning: Date { calendar.date(from: DateComponents(year: 2026, month: 10, day: 27, hour: 7))! }

    /// The college titles the feeds produce; none may leave CollegeStore or the device.
    private let collegeTitles = [
        "Canary camera kit", "Canary loans desk", "Camera kit (demo)", "Tripod and lights (demo)",
        "Visual culture essay draft", "Studio portfolio upload", "Reading week briefing",
    ]

    @MainActor
    private struct Harness {
        let model: AppModel
        let secrets: MemorySecrets
        let feeds: StubFeeds
        let scheduler: SpyDeadlineScheduler
        let local: SpyProvider
        let cloud: SpyProvider
        var services: AppServices { model.services }
    }

    private func makeHarness(phrasing: BriefPhrasingMode = .off) throws -> Harness {
        let secrets = MemorySecrets()
        let feeds = StubFeeds(now: morning, calendar: calendar)
        let scheduler = SpyDeadlineScheduler()
        let local = SpyProvider(.onDevice)
        let cloud = SpyProvider(.anthropicCloud(region: "global"))
        let services = try AppServices.make(
            inMemory: true, secrets: secrets, eventStore: DemoEventStore(now: morning, calendar: calendar, richWeek: true),
            deadlineNotifications: scheduler, providers: [local, cloud], feedTransport: feeds
        )
        let defaults = UserDefaults(suiteName: "eagar.tests.\(UUID().uuidString)")!
        defaults.set(true, forKey: PlannerModel.notificationsRequestedKey)
        var settings = BriefSettings()
        settings.phrasingMode = phrasing
        settings.save(to: defaults)
        let model = AppModel(services: services, defaults: defaults, clock: FixedTestClock(date: morning), calendar: calendar)
        return Harness(model: model, secrets: secrets, feeds: feeds, scheduler: scheduler, local: local, cloud: cloud)
    }

    /// Connects cdbooking (with an API token: the JSON path) and Canvas.
    private func connectBoth(_ h: Harness) async throws {
        await h.model.planner.refresh()
        #expect(await h.model.feeds.connectBooking(feedURL: StubFeeds.feedURL, apiToken: StubFeeds.apiToken))
        #expect(await h.model.feeds.connectCanvas(feedURL: StubFeeds.canvasURL))
        h.model.applySources()
    }

    @Test func Boundary_B8_feedRecordsLiveOnlyInCollegeStore() async throws {
        let h = try makeHarness()
        try await connectBoth(h)
        let stores = h.services.stores

        #expect(try await rows(stores.personal, BookingItem.self) { $0.bookingID }.isEmpty)
        #expect(try await rows(stores.personal, CanvasItem.self) { $0.uid }.isEmpty)
        #expect(try await rows(stores.personal, FeedSourceRecord.self) { $0.kindRaw }.isEmpty)
        let personalOrigins = try await rows(stores.personal, Deadline.self) { $0.originRaw }
        #expect(!personalOrigins.contains(DeadlineOrigin.booking.rawValue) && !personalOrigins.contains(DeadlineOrigin.canvas.rawValue))

        let bookings = try await rows(stores.college, BookingItem.self) { $0.dataClass }
        let canvas = try await rows(stores.college, CanvasItem.self) { $0.dataClass }
        let sources = try await rows(stores.college, FeedSourceRecord.self) { $0.dataClass }
        let deadlines = try await rows(stores.college, Deadline.self) { ($0.originRaw, $0.dataClass) }
        #expect(bookings == [.college])
        #expect(canvas.count == 3 && canvas.allSatisfy { $0 == .college })
        #expect(sources.count == 2 && sources.allSatisfy { $0 == .college })
        #expect(deadlines.filter { $0.0 == DeadlineOrigin.booking.rawValue }.count == 1)
        #expect(deadlines.filter { $0.0 == DeadlineOrigin.canvas.rawValue }.count == 2) // assignments only
        #expect(deadlines.allSatisfy { $0.1 == .college })

        // The Deadlines tab shows them as college deadlines.
        let rows = h.model.planner.deadlines.filter { $0.snapshot.origin == .booking || $0.snapshot.origin == .canvas }
        #expect(rows.count == 3 && rows.allSatisfy { $0.snapshot.dataClass == .college })
    }

    /// The sync spy: a SyncCoordinator over PersonalStore with the app's own adapters (what
    /// CKSyncEngine would be handed) finds the personal deadline and nothing from the feeds, and
    /// CollegeStore cannot be attached to a sync engine at all.
    @Test func Boundary_B8_feedRecordsNeverEnterTheSyncEngine() async throws {
        let h = try makeHarness()
        try await connectBoth(h)
        var personal = DeadlineDraft(dueAt: morning.addingTimeInterval(86_400))
        personal.title = "Renew passport"
        #expect(await h.model.planner.save(personal))

        let spy = try SyncCoordinator(store: h.services.stores.personal, adapters: AppServices.syncAdapters, stateURL: nil)
        let changes = try await spy.scanLocalChanges()
        var uploaded: [String] = []
        for case let .save(name) in changes {
            let record = try #require(await spy.record(for: name))
            for key in record.allKeys() { uploaded.append(String(describing: record[key] ?? "")) }
            for key in record.encryptedValues.allKeys() { uploaded.append(String(describing: record.encryptedValues[key] ?? "")) }
        }
        #expect(uploaded.contains { $0.contains("Renew passport") }) // the spy does see personal records
        for value in uploaded {
            for title in collegeTitles { #expect(!value.contains(title), "\(value)") }
        }
        let feedDeadlineIDs = h.model.planner.deadlines.filter { $0.snapshot.origin != .manual }.map(\.id.uuidString)
        #expect(changes.allSatisfy { change in
            guard case let .save(name) = change else { return true }
            return !feedDeadlineIDs.contains { name.contains($0) }
        })

        #expect(throws: StoreError.syncForbidden(.college)) {
            _ = try SyncCoordinator(store: h.services.stores.college, adapters: AppServices.syncAdapters, stateURL: nil)
        }
        #expect(!SyncRegistry.registeredStores.contains(.college))
    }

    /// A brief phrasing pass with Claude allowed for personal items (consent granted, cloud
    /// provider reachable): loan and Canvas lines go to the on-device model only.
    @Test func Boundary_B8_feedTitlesNeverReachACloudModel() async throws {
        let h = try makeHarness(phrasing: .claudeForPersonal)
        try h.secrets.set(Secret("test-canary-claude-key-0000"), for: .anthropicAPIKey)
        try await h.services.consents.grant(ConsentKey(sourceID: nil, purpose: .briefPhrase, tier: .anthropicCloud), textVersion: 1)
        try await connectBoth(h)
        var personal = DeadlineDraft(dueAt: morning.addingTimeInterval(2 * 86_400))
        personal.title = "Renew passport"
        #expect(await h.model.planner.save(personal))
        h.model.applySources()

        let brief = try #require(h.model.planner.brief)
        let loans = try #require(brief.sections.first { $0.kind == .loans })
        #expect(loans.items.map(\.title).contains("Canary camera kit"))
        #expect(brief.allItems.contains { $0.title.hasPrefix("Visual culture essay draft") })

        _ = await BriefPhraser.phrase(brief, mode: .claudeForPersonal, router: h.services.router, calendar: calendar)
        #expect(!h.cloud.recorded.isEmpty) // personal lines did use Claude, so the test is not vacuous
        for call in h.cloud.recorded {
            #expect(call.payloads.allSatisfy { $0.dataClass != .college })
            for title in collegeTitles {
                #expect(!call.wire.contains(title))
                #expect(!call.payloads.contains { $0.text.contains(title) })
            }
        }
        #expect(h.local.recorded.contains { call in call.payloads.contains { $0.text.contains("Canary camera kit") } })
    }

    /// M2 acceptance: feed secrets are in the Keychain (SecretKeys), not in SwiftData.
    @Test func Boundary_B8_feedSecretsAreInTheKeychainNotSwiftData() async throws {
        let h = try makeHarness()
        try await connectBoth(h)
        let booking = try #require(h.model.feeds.booking?.source.id)
        let canvas = try #require(h.model.feeds.canvas?.source.id)
        #expect(try h.secrets.get(.cdbookingFeedURL(booking))?.reveal() == StubFeeds.feedURL)
        #expect(try h.secrets.get(.cdbookingAPIToken(booking))?.reveal() == StubFeeds.apiToken)
        #expect(try h.secrets.get(.canvasFeedURL(canvas))?.reveal() == StubFeeds.canvasURL)

        // Settings shows them masked only.
        #expect(h.model.feeds.maskedBookingToken?.contains(StubFeeds.apiToken) == false)
        #expect(h.model.feeds.maskedBookingFeedURL?.contains(StubFeeds.feedToken) == false)
        #expect(h.model.feeds.maskedCanvasFeedURL?.contains("canary-5b8e") == false)

        var stored: [String] = []
        for store in [h.services.stores.college, h.services.stores.personal] {
            stored += try await rows(store, BookingItem.self) {
                [$0.bookingID, $0.title, $0.location ?? "", $0.bookingPageURL ?? "", $0.extendPageURL ?? ""] + $0.itemNames
            }.flatMap { $0 }
            stored += try await rows(store, CanvasItem.self) { [$0.uid, $0.title, $0.pageURL ?? ""] }.flatMap { $0 }
            stored += try await rows(store, FeedSourceRecord.self) {
                [$0.displayName, $0.etag ?? "", $0.fallbackETag ?? "", $0.cursor ?? ""]
            }.flatMap { $0 }
            stored += try await rows(store, Deadline.self) { $0.title }
        }
        #expect(!stored.isEmpty)
        for value in stored {
            for secret in [StubFeeds.feedToken, StubFeeds.apiToken, "canary-5b8e"] { #expect(!value.contains(secret), "\(value)") }
        }

        // Remove deletes the secrets and the records.
        await h.model.feeds.removeBooking()
        await h.model.feeds.removeCanvas()
        #expect(try h.secrets.get(.cdbookingFeedURL(booking)) == nil)
        #expect(try h.secrets.get(.cdbookingAPIToken(booking)) == nil)
        #expect(try h.secrets.get(.canvasFeedURL(canvas)) == nil)
        #expect(try await rows(h.services.stores.college, BookingItem.self) { $0.bookingID }.isEmpty)
        #expect(try await rows(h.services.stores.college, CanvasItem.self) { $0.uid }.isEmpty)
        #expect(h.model.planner.deadlines.allSatisfy { $0.snapshot.origin == .manual })
    }

    /// FR-BOOK-03: return reminders at 24 h and 2 h through the deadline notification path,
    /// content-free because loans are college (BD-04).
    @Test func FR_BOOK_03_returnRemindersAreContentFree() async throws {
        let h = try makeHarness()
        try await connectBoth(h)
        let loan = try #require(h.model.planner.deadlines.first { $0.snapshot.origin == .booking })
        let planned = h.scheduler.added.withLock { $0 }.filter { $0.deadlineID == loan.id }
        // Due at 17:00 today: the 2-hour reminder is ahead, the 24-hour one has passed.
        #expect(loan.snapshot.reminderOffsetsMinutes == LoanReminders.defaultOffsetsMinutes)
        #expect(planned.map(\.offsetMinutes) == [120])
        let all = h.scheduler.added.withLock { $0 }
        #expect(!all.isEmpty)
        for notification in all {
            for title in collegeTitles {
                #expect(!notification.title.contains(title) && !notification.body.contains(title))
            }
        }
    }

    /// FR-BOOK-04: a loan due during tomorrow's portfolio reviews gets an earlier return slot,
    /// and accepting it adds a local college return reminder.
    @Test func FR_BOOK_04_clashProposalCanBeAccepted() async throws {
        let h = try makeHarness()
        await h.model.planner.refresh()
        // No API token: the iCal feed, which has the loan due tomorrow at noon.
        #expect(await h.model.feeds.connectBooking(feedURL: StubFeeds.feedURL, apiToken: ""))
        #expect(h.model.feeds.lastBookingPath == .iCalendar)
        let tripod = try #require(h.model.feeds.loans.first { $0.booking.title == "Tripod and lights (demo)" })
        let clash = try #require(h.model.feeds.clashes[tripod.booking.id])
        let slot = try #require(clash.proposedSlot)
        #expect(slot.end <= tripod.booking.due!)
        #expect(clash.dataClass == .college)
        let row = try #require(h.model.planner.deadlines.first { $0.snapshot.origin == .booking && $0.snapshot.title == "Tripod and lights (demo)" })
        #expect(h.model.feeds.loanInfo(forDeadline: row.id)?.proposalAccepted == false)

        await h.model.feeds.acceptProposedReturn(bookingID: tripod.booking.id)
        let reminder = try #require(h.model.planner.deadlines.first { $0.snapshot.title == "Return Tripod and lights (demo)" })
        #expect(reminder.snapshot.dataClass == .college)
        #expect(reminder.snapshot.dueAt == slot.start)
        #expect(h.model.feeds.loanInfo(forDeadline: row.id)?.proposalAccepted == true)
        // Accepting again adds nothing.
        await h.model.feeds.acceptProposedReturn(bookingID: tripod.booking.id)
        #expect(h.model.planner.deadlines.filter { $0.snapshot.title == "Return Tripod and lights (demo)" }.count == 1)
    }

    /// FR-BOOK-02 / Appendix E.2: a revoked token is a visible health state, not a silent failure.
    @Test func FR_BOOK_02_revokedTokenIsShownAsFeedHealth() async throws {
        let h = try makeHarness()
        try await connectBoth(h)
        #expect(h.model.feeds.booking?.health == .ok)
        #expect(h.model.feeds.adminSummary?.pendingApprovals == 3)
        h.feeds.revoked.withLock { $0 = true }
        await h.model.feeds.refresh(force: true)
        #expect(h.model.feeds.booking?.health == .unauthorised)
        #expect(h.model.feeds.needsAttention)
        // The loans already fetched stay until the token is replaced.
        #expect(!h.model.feeds.activeLoans.isEmpty)
    }

    @Test func invalidFeedAddressIsRefusedAndNothingIsStored() async throws {
        let h = try makeHarness()
        #expect(await !h.model.feeds.connectCanvas(feedURL: "http://canvas.example.invalid/feed.ics"))
        #expect(h.model.feeds.failure == .invalidURL)
        #expect(h.model.feeds.canvas == nil)
    }

    /// An all-day deadline due today (how Canvas all-day due dates arrive, at 00:00) is
    /// upcoming until the day ends, not overdue from midnight.
    @Test func allDayDeadlineDueTodayIsNotOverdue() async throws {
        let h = try makeHarness()
        var draft = DeadlineDraft(dueAt: calendar.startOfDay(for: morning))
        draft.title = "Essay draft"
        draft.isAllDay = true
        draft.dataClass = .college
        #expect(await h.model.planner.save(draft))
        #expect(h.model.planner.overdueDeadlines.isEmpty)
        #expect(h.model.planner.upcomingDeadlines.map(\.snapshot.title) == ["Essay draft"])
    }
}
