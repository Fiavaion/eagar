import EagarCalendar
import EagarCore
import EagarStore
import Foundation
import SwiftData
import Testing
@testable import EagarFeeds

private func makeStores() throws -> EagarStores {
    try EagarStores(location: .inMemory, models: [Deadline.self, FeedSourceRecord.self])
}

private let now = Date(timeIntervalSince1970: 1_793_000_000)

struct FeedDeadlineTests {
    @Test func stableIDsAreDeterministicAndDistinct() {
        let source = SourceID(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!)
        let a = FeedDeadline.deadlineID(origin: .booking, sourceID: source, externalID: "b_1")
        #expect(a == FeedDeadline.deadlineID(origin: .booking, sourceID: source, externalID: "b_1"))
        #expect(a != FeedDeadline.deadlineID(origin: .canvas, sourceID: source, externalID: "b_1"))
        #expect(a != FeedDeadline.deadlineID(origin: .booking, sourceID: SourceID(), externalID: "b_1"))
        #expect(a.uuidString.dropFirst(14).first == "8")
        #expect(StableID.uuid("a", "bc") != StableID.uuid("ab", "c"))
    }

    /// FR-CORE-03: a feed deadline takes the class of its item (taint rule).
    @Test(arguments: DataClass.allCases)
    func Derivation_feedDeadline(_ itemClass: DataClass) {
        let deadline = FeedDeadline(origin: .canvas, sourceID: SourceID(), externalID: "x", title: "t", dueAt: now, isAllDay: false, itemClass: itemClass)
        #expect(deadline.dataClass == itemClass)
        #expect(deadline.snapshot.dataClass == itemClass)
        #expect(deadline.snapshot.status == .open)
    }

    @Test func upsertInsertsUpdatesClosesAndPreservesMarksState() async throws {
        let stores = try makeStores()
        let reconciler = FeedDeadlineReconciler(stores: stores)
        let source = SourceID()
        func item(_ id: String, due: Date, closed: Bool = false, title: String = "Loan") -> FeedDeadline {
            FeedDeadline(origin: .booking, sourceID: source, externalID: id, title: title, dueAt: due, isAllDay: false, itemClass: .college, reminderOffsetsMinutes: [1440, 120], isClosed: closed)
        }
        var counts = try await reconciler.upsert([item("1", due: now), item("2", due: now)], now: now)
        #expect(counts.inserted == 2)

        // Mark snoozes and edits offsets on deadline 2; the feed must not undo that.
        let id2 = FeedDeadline.deadlineID(origin: .booking, sourceID: source, externalID: "2")
        try await stores.college.perform { context in
            let d = try context.fetch(FetchDescriptor<Deadline>(predicate: #Predicate { $0.deadlineUUID == id2 })).first!
            d.snooze(until: now.addingTimeInterval(60))
            d.reminderOffsetsMinutes = [30]
        }

        counts = try await reconciler.upsert([item("1", due: now.addingTimeInterval(3600), title: "Loan renamed"), item("2", due: now, closed: true)], now: now)
        #expect(counts.inserted == 0)
        #expect(counts.updated == 1)
        #expect(counts.closed == 1)

        let rows = try await stores.college.fetch(FetchDescriptor<Deadline>(sortBy: [SortDescriptor(\.dueAt)])) { $0.snapshot }
        #expect(rows.count == 2)
        let first = try #require(rows.first { $0.title == "Loan renamed" })
        #expect(first.dueAt == now.addingTimeInterval(3600))
        #expect(first.origin == .booking)
        #expect(first.dataClass == .college)
        #expect(first.reminderOffsetsMinutes == [1440, 120])
        let second = try #require(rows.first { $0.id == id2 })
        #expect(second.status == .done)
        #expect(second.reminderOffsetsMinutes == [30])
        #expect(try await stores.personal.fetch(FetchDescriptor<Deadline>()) { $0.title }.isEmpty)
    }

    @Test func fullReplaceDeletesOnlyThisSourcesMissingDeadlines() async throws {
        let stores = try makeStores()
        let reconciler = FeedDeadlineReconciler(stores: stores)
        let source = SourceID(), other = SourceID()
        let a = FeedDeadline(origin: .canvas, sourceID: source, externalID: "a", title: "A", dueAt: now, isAllDay: true, itemClass: .college)
        let b = FeedDeadline(origin: .canvas, sourceID: source, externalID: "b", title: "B", dueAt: now, isAllDay: false, itemClass: .college)
        let c = FeedDeadline(origin: .canvas, sourceID: other, externalID: "c", title: "C", dueAt: now, isAllDay: false, itemClass: .college)
        _ = try await reconciler.upsert([a, b, c], now: now)
        try await stores.insert(Deadline(title: "Manual", dueAt: now, dataClass: .college, createdAt: now))

        let counts = try await reconciler.upsert([a], replacingAllFrom: (.canvas, source), now: now)
        #expect(counts.deleted == 1)
        let titles = try await stores.college.fetch(FetchDescriptor<Deadline>()) { $0.title }
        #expect(Set(titles) == ["A", "C", "Manual"])

        #expect(try await reconciler.remove(ids: [c.id]) == 1)
        #expect(try await reconciler.removeAll(origin: .canvas, source: source) == 1)
        #expect(try await stores.college.fetch(FetchDescriptor<Deadline>()) { $0.title } == ["Manual"])
    }

    @Test func Boundary_B8_collegeFeedDeadlinesNeverLandInPersonalStore() async throws {
        let stores = try makeStores()
        let item = FeedDeadline(origin: .booking, sourceID: SourceID(), externalID: "1", title: "Kit", dueAt: now, isAllDay: false, itemClass: .college)
        _ = try await FeedDeadlineReconciler(stores: stores).upsert([item], now: now)
        #expect(try await stores.personal.fetch(FetchDescriptor<Deadline>()) { $0.title }.isEmpty)
        #expect(try await stores.college.fetch(FetchDescriptor<Deadline>()) { $0.dataClass } == [.college])
    }
}

struct FeedSourceRegistryTests {
    @Test func collegeSourcesLiveInCollegeStoreOnePerSource() async throws {
        let stores = try makeStores()
        let registry = FeedSourceRegistry(stores: stores)
        let source = FeedSource.proposed(kind: .cdbooking, host: "cdbooking.com", profile: .owner)
        try await registry.register(source, displayName: "Bookings", at: now)
        try await registry.register(source, displayName: "NCAD bookings", at: now)

        #expect(try await stores.personal.fetch(FetchDescriptor<FeedSourceRecord>()) { $0.displayName }.isEmpty)
        #expect(try await stores.college.fetch(FetchDescriptor<FeedSourceRecord>()) { $0.displayName } == ["NCAD bookings"])

        var state = try #require(try await registry.state(of: source.id))
        #expect(state.source == source)
        #expect(state.health == .unknown)
        state.etag = "\"e1\""
        state.cursor = "2026-10-25T09:00:00Z"
        state.health = .unauthorised
        try await registry.save(state)
        let reread = try #require(try await registry.state(of: source.id))
        #expect(reread.etag == "\"e1\"")
        #expect(reread.cursor == "2026-10-25T09:00:00Z")
        #expect(reread.health.needsAttention)
        #expect(try await registry.all().count == 1)

        try await registry.remove(source.id)
        #expect(try await registry.state(of: source.id) == nil)
    }

    /// Invariant 6: the persisted source has nowhere to put a URL or token.
    @Test func Boundary_B8_sourceRecordHasNoSecretFields() {
        let record = FeedSourceRecord(source: FeedSource(kind: .canvas, dataClass: .college, processingMode: .localAI), displayName: "Canvas", createdAt: now)
        let names = Mirror(reflecting: record).children.compactMap(\.label).map { $0.lowercased() }
        #expect(!names.isEmpty)
        for name in names {
            #expect(!name.contains("token") && !name.contains("url") && !name.contains("secret") && !name.contains("password"), "\(name)")
        }
    }
}
