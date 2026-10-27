import EagarCalendar
import EagarCore
import EagarFeeds
import EagarStore
import EagarTestSupport
import Foundation
import SwiftData
import Testing
@testable import EagarBookings

/// FR-BOOK-02/03, FR-DL-01 (origin booking): refresh into CollegeStore.
struct BookingSyncTests {
    private func deadlines(_ h: BookingHarness) async throws -> [DeadlineSnapshot] {
        try await h.stores.college.fetch(FetchDescriptor<Deadline>()) { $0.snapshot }
    }

    @Test func refreshStoresBookingsAndLoanDeadlinesThenTracksChanges() async throws {
        let h = try BookingHarness()
        try await h.register()
        h.seed()

        let first = try await h.sync.refresh(h.source)
        #expect(first.path == .json && first.changed && first.upserted == 4)
        #expect(first.deadlines.inserted == 1)

        let repo = BookingRepository(stores: h.stores)
        // Ordered by due, end or start: light kit 22 Oct, room ends 28 Oct 12:00, kit due 28 Oct 16:00, tripod 2 Nov.
        #expect(try await repo.all().map(\.id) == ["b_792", "b_790", "b_789", "b_791"])
        #expect(try await repo.activeLoans().map(\.id) == ["b_789"])

        // One deadline: the active loan, with 24 h / 2 h return reminders, college.
        let loanDeadlines = try await deadlines(h)
        let loan = try #require(loanDeadlines.first)
        #expect(loanDeadlines.count == 1)
        #expect(loan.origin == .booking)
        #expect(loan.dueAt == utcDate(2026, 10, 28, 16))
        #expect(loan.reminderOffsetsMinutes == [1440, 120])
        #expect(loan.dataClass == .college)
        #expect(loan.id == FeedDeadline.deadlineID(origin: .booking, sourceID: h.sourceID, externalID: "b_789"))

        var state = try #require(try await FeedSourceRegistry(stores: h.stores).state(of: h.sourceID))
        #expect(state.health == .ok && state.cursor == "2026-10-27T09:00:00Z" && state.etag != nil && state.lastSuccessAt == fixtureNow)

        // Nothing new: 304, nothing changes.
        let second = try await h.sync.refresh(h.source)
        #expect(!second.changed)

        // The loan is returned and the request is withdrawn.
        h.clock.advance(by: 3600)
        h.server.put(.init(id: "b_789", status: "returned", title: "Synthetic camera kit", start: utcDate(2026, 10, 26, 10),
                           due: utcDate(2026, 10, 28, 16), returnedAt: h.clock.now()))
        h.server.remove(id: "b_791")
        let third = try await h.sync.refresh(h.source)
        #expect(third.path == .json && third.upserted == 1 && third.deleted == 1 && third.deadlines.closed == 1)
        #expect(try await repo.all().map(\.id) == ["b_792", "b_790", "b_789"])
        #expect(try await deadlines(h).first?.status == .done)
        #expect(try await repo.activeLoans().isEmpty)
        state = try #require(try await FeedSourceRegistry(stores: h.stores).state(of: h.sourceID))
        #expect(state.cursor == "2026-10-27T10:00:00Z")
    }

    @Test func iCalSnapshotReplacesEverything() async throws {
        let h = try BookingHarness(withAPIToken: false)
        try await h.register()
        h.seed()
        try await h.sync.refresh(h.source)
        h.clock.advance(by: 60)
        h.server.remove(id: "b_789")
        let outcome = try await h.sync.refresh(h.source)
        #expect(outcome.path == .iCalendar && outcome.deleted == 1 && outcome.deadlines.deleted == 1)
        #expect(try await BookingRepository(stores: h.stores).all().map(\.id).contains("b_789") == false)
        #expect(try await deadlines(h).isEmpty)
    }

    @Test func revocationIsRecordedAsHealth() async throws {
        let h = try BookingHarness()
        try await h.register()
        h.server.setMode(.tokenRevoked)
        await #expect(throws: BookingSyncError.source(.unauthorised)) { try await h.sync.refresh(h.source) }
        let state = try #require(try await FeedSourceRegistry(stores: h.stores).state(of: h.sourceID))
        #expect(state.health == .unauthorised && state.health.needsAttention)
        #expect(state.lastAttemptAt == fixtureNow && state.lastSuccessAt == nil)
    }

    @Test func unregisteredSourceIsRefused() async throws {
        let h = try BookingHarness()
        await #expect(throws: BookingSyncError.notRegistered) { try await h.sync.refresh(h.source) }
    }

    @Test func adminScopeIsRecorded() async throws {
        let h = try BookingHarness(adminScope: true)
        try await h.register()
        h.server.setAdmin(scope: true, pendingApprovals: 3, overdueReturns: 1)
        let summary = try await h.sync.refreshAdminSummary(h.source)
        #expect(summary?.pendingApprovals == 3)
        #expect(try await FeedSourceRegistry(stores: h.stores).state(of: h.sourceID)?.hasAdminScope == true)
    }

    @Test func disconnectRemovesEverythingForTheSource() async throws {
        let h = try BookingHarness()
        try await h.register()
        h.seed()
        try await h.sync.refresh(h.source)
        try await h.sync.disconnect(h.sourceID)
        try CDBookingSecrets(store: h.secrets).delete(for: h.sourceID)
        #expect(try await BookingRepository(stores: h.stores).all().isEmpty)
        #expect(try await deadlines(h).isEmpty)
        #expect(try await FeedSourceRegistry(stores: h.stores).state(of: h.sourceID) == nil)
        #expect(try h.secrets.get(.cdbookingFeedURL(h.sourceID)) == nil)
        #expect(try h.secrets.get(.cdbookingAPIToken(h.sourceID)) == nil)
    }

    /// FR-BOOK-08: consumers work with any `BookingSource`, not only cdbooking.
    @Test func anyBookingSourceCanBeSynced() async throws {
        struct NativeReplacementStub: BookingSource {
            let sourceID: SourceID
            func fetchChanges(since cursor: BookingCursor) async throws(BookingSourceError) -> BookingChanges {
                .snapshot(bookings: [BookingRecord(id: "n1", kind: .equipment, status: .checkedOut, title: "Synthetic kit", due: utcDate(2026, 10, 29, 12))],
                          cursor: BookingCursor(since: "x"), path: .json)
            }
            func adminSummary() async throws(BookingSourceError) -> AdminSummary? { nil }
        }
        let h = try BookingHarness()
        try await h.register()
        let outcome = try await h.sync.refresh(NativeReplacementStub(sourceID: h.sourceID))
        #expect(outcome.upserted == 1)
        #expect(try await BookingRepository(stores: h.stores).activeLoans().map(\.id) == ["n1"])
    }
}
