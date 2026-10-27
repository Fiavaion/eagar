import EagarCalendar
import EagarCore
import EagarFeeds
import EagarSecurity
import EagarStore
import EagarSync
import EagarTestSupport
import Foundation
import SwiftData
import Testing
@testable import EagarBookings

/// B-8 (package level): cdbooking records are college, CollegeStore-only, never synced, and
/// their secrets live only in the secret store. The end-to-end half (RecordingProvider and a
/// sync spy over the app) is done at app level.
struct BookingBoundaryTests {
    @Test func Boundary_B8_bookingRecordsAreCollege() {
        let item = BookingItem(BookingRecord(id: "b", kind: .equipment, status: .checkedOut, title: "Synthetic"), source: SourceID(), fetchedAt: fixtureNow)
        #expect(item.dataClass == .college)
        #expect(BookingSnapshot(sourceID: SourceID(), booking: item.record).dataClass == .college)
        #expect(FeedSource(kind: .cdbooking, dataClass: .personal, processingMode: .cloudAllowed).dataClass == .college)
    }

    @Test func Boundary_B8_personalStoreRefusesBookings() async throws {
        let h = try BookingHarness()
        let source = h.sourceID
        await #expect(throws: StoreError.classMismatch(store: .personal, dataClass: .college)) {
            try await h.stores.personal.insert(BookingItem(BookingRecord(id: "b", kind: .equipment, status: .checkedOut, title: "Synthetic"), source: source, fetchedAt: fixtureNow))
        }
        await #expect(throws: StoreError.classMismatch(store: .personal, dataClass: .college)) {
            try await h.stores.personal.insert(FeedSourceRecord(source: FeedSource(kind: .cdbooking, dataClass: .college, processingMode: .localAI), displayName: "B", createdAt: fixtureNow))
        }
    }

    @Test func Boundary_B8_refreshWritesNothingToPersonalStore() async throws {
        let h = try BookingHarness()
        try await h.register()
        h.seed()
        try await h.sync.refresh(h.source)
        #expect(try await h.stores.personal.fetch(FetchDescriptor<BookingItem>()) { $0.bookingID }.isEmpty)
        #expect(try await h.stores.personal.fetch(FetchDescriptor<Deadline>()) { $0.title }.isEmpty)
        #expect(try await h.stores.personal.fetch(FetchDescriptor<FeedSourceRecord>()) { $0.displayName }.isEmpty)
        #expect(try await h.stores.college.fetch(FetchDescriptor<BookingItem>()) { $0.dataClass }.allSatisfy { $0 == .college })
        #expect(try await h.stores.college.fetch(FetchDescriptor<Deadline>()) { $0.dataClass } == [.college])
    }

    /// CollegeStore cannot be attached to a sync engine, so bookings cannot enter CKSyncEngine.
    @Test func Boundary_B8_collegeStoreCannotBeSynced() throws {
        let stores = try EagarStores(location: .inMemory, models: [BookingItem.self, FeedSourceRecord.self, Deadline.self])
        #expect(throws: StoreError.syncForbidden(.college)) { try SyncRegistry.register(stores.college, engine: "spy") }
        #expect(throws: StoreError.syncForbidden(.college)) {
            _ = try SyncCoordinator(store: stores.college, adapters: [AnySyncAdapter(DeadlineSyncAdapter())], stateURL: nil)
        }
        #expect(!SyncRegistry.registeredStores.contains(.college))
    }

    /// Invariant 6 / M2 acceptance: the token and feed URL are in the secret store, and nowhere
    /// in any persisted record.
    @Test func Boundary_B8_feedSecretsInKeychainNotSwiftData() async throws {
        let h = try BookingHarness(adminScope: true)
        try await h.register()
        h.seed()
        h.server.setAdmin(scope: true, pendingApprovals: 1, overdueReturns: 1)
        try await h.sync.refresh(h.source)
        _ = try await h.sync.refreshAdminSummary(h.source)

        #expect(try h.secrets.get(.cdbookingAPIToken(h.sourceID))?.reveal() == h.server.apiToken)
        #expect(try h.secrets.get(.cdbookingFeedURL(h.sourceID))?.reveal() == h.server.feedURL)

        var stored: [String] = []
        for store in [h.stores.college, h.stores.personal] {
            stored += try await store.fetch(FetchDescriptor<BookingItem>()) {
                [$0.bookingID, $0.kindRaw, $0.statusRaw, $0.title, $0.department ?? "", $0.location ?? "",
                 $0.bookingPageURL ?? "", $0.extendPageURL ?? "", $0.dataClassRaw] + $0.itemNames
            }.flatMap { $0 }
            stored += try await store.fetch(FetchDescriptor<FeedSourceRecord>()) {
                [$0.kindRaw, $0.displayName, $0.dataClassRaw, $0.processingModeRaw, $0.etag ?? "", $0.fallbackETag ?? "", $0.cursor ?? "", $0.healthRaw]
            }.flatMap { $0 }
            stored += try await store.fetch(FetchDescriptor<Deadline>()) { [$0.title, $0.originRaw, $0.dataClassRaw] }.flatMap { $0 }
        }
        #expect(!stored.isEmpty)
        for value in stored {
            #expect(!value.contains(h.server.apiToken) && !value.contains(h.server.feedToken) && !value.contains("/ical/"), "\(value)")
        }
        for type in [Mirror(reflecting: BookingItem(BookingRecord(id: "x", kind: .room, status: .approved, title: ""), source: SourceID(), fetchedAt: fixtureNow))] {
            for label in type.children.compactMap(\.label).map({ $0.lowercased() }) {
                #expect(!label.contains("token") && !label.contains("secret") && !label.contains("feedurl"), "\(label)")
            }
        }
    }

    @Test func Boundary_B8_logsCarryNoContentOrSecrets() async throws {
        let capture = LogCapture()
        let token = EagarLog.addSink(capture)
        defer { EagarLog.removeSink(token) }

        let h = try BookingHarness()
        try await h.register()
        h.seed()
        try await h.sync.refresh(h.source)
        h.server.setMode(.malformedJSON)
        h.clock.advance(by: 60)
        try await h.sync.refresh(h.source)
        h.server.setMode(.tokenRevoked)
        _ = try? await h.sync.refresh(h.source)

        let texts = capture.texts
        #expect(texts.contains { $0.contains("booking refresh") })
        let forbidden = [h.server.apiToken, h.server.feedToken, h.server.host, "Synthetic", "Returns desk", "Studio", "b_789"]
        for text in texts {
            for word in forbidden { #expect(!text.contains(word), "\(text)") }
        }
    }
}
