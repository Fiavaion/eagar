import EagarCalendar
import EagarCore
import EagarFeeds
import EagarStore
import EagarTestSupport
import Foundation
import SwiftData
import Testing
@testable import EagarBookings

/// A source that changes the stored source record's class behind the store's back, then fails
/// with 401, so recording the health fails the store's class check.
private struct HealthSaveSaboteur: BookingSource {
    let sourceID: SourceID
    let container: ModelContainer

    func fetchChanges(since cursor: BookingCursor) async throws(BookingSourceError) -> BookingChanges {
        let context = ModelContext(container)
        let id = sourceID.rawValue
        if let records = try? context.fetch(FetchDescriptor<FeedSourceRecord>(predicate: #Predicate { $0.sourceUUID == id })) {
            records.forEach { $0.dataClassRaw = DataClass.personal.rawValue }
            try? context.save()
        }
        throw .unauthorised
    }

    func adminSummary() async throws(BookingSourceError) -> AdminSummary? { nil }
}

/// Fixes from the fresh-context review of the merged feed packages.
struct BookingReviewFixTests {
    private func loanDeadline(_ h: BookingHarness) async throws -> DeadlineSnapshot? {
        let id = FeedDeadline.deadlineID(origin: .booking, sourceID: h.sourceID, externalID: "b_789")
        return try await h.stores.college.fetch(FetchDescriptor<Deadline>(predicate: #Predicate { $0.deadlineUUID == id })) { $0.snapshot }.first
    }

    private func putKit(_ h: BookingHarness, status: String, returnedAt: Date? = nil) {
        h.clock.advance(by: 3600)
        h.server.put(.init(id: "b_789", status: status, title: "Synthetic camera kit", location: "Returns desk",
                           start: utcDate(2026, 10, 26, 10), due: utcDate(2026, 10, 28, 16), returnedAt: returnedAt, updatedAt: h.clock.now()))
    }

    /// A wrongly scanned return corrected back to checked out reopens the loan deadline, so the
    /// 24 h / 2 h return reminders fire again (FR-BOOK-03).
    @Test func FR_BOOK_03_returnCorrectedToCheckedOutReopensTheDeadline() async throws {
        let h = try BookingHarness()
        try await h.register()
        h.seed()
        try await h.sync.refresh(h.source)
        #expect(try await loanDeadline(h)?.status == .open)

        putKit(h, status: "returned", returnedAt: h.clock.now())
        try await h.sync.refresh(h.source)
        #expect(try await loanDeadline(h)?.status == .done)

        putKit(h, status: "checked_out")
        let outcome = try await h.sync.refresh(h.source)
        #expect(outcome.deadlines.reopened == 1)
        #expect(try await loanDeadline(h)?.status == .open)
    }

    /// Mark marking a loan done himself is kept while the feed keeps saying checked out.
    @Test func doneByMarkIsKeptWhileTheLoanStaysOpen() async throws {
        let h = try BookingHarness()
        try await h.register()
        h.seed()
        try await h.sync.refresh(h.source)
        let id = FeedDeadline.deadlineID(origin: .booking, sourceID: h.sourceID, externalID: "b_789")
        let now = h.clock.now()
        try await h.stores.college.perform { context in
            try context.fetch(FetchDescriptor<Deadline>(predicate: #Predicate { $0.deadlineUUID == id })).forEach { $0.markDone(at: now) }
        }
        putKit(h, status: "checked_out")
        let outcome = try await h.sync.refresh(h.source)
        #expect(outcome.deadlines.reopened == 0)
        #expect(try await loanDeadline(h)?.status == .done)
    }

    /// A failed health save ("token revoked") is not swallowed: the store failure is thrown.
    @Test func failedHealthSaveIsReported() async throws {
        let h = try BookingHarness()
        try await h.register()
        let saboteur = HealthSaveSaboteur(sourceID: h.sourceID, container: h.stores.college.modelContainer)
        await #expect(throws: BookingSyncError.store(.classMismatch(store: .college, dataClass: .personal))) {
            try await h.sync.refresh(saboteur)
        }
    }
}

/// FR-BOOK-04: an accepted return reminder belongs to its loan.
struct ReturnReminderLifecycleTests {
    private func reminder(_ h: BookingHarness) async throws -> DeadlineSnapshot? {
        let id = LoanReminders.returnReminderID(source: h.sourceID, bookingID: "b_789")
        return try await h.stores.college.fetch(FetchDescriptor<Deadline>(predicate: #Predicate { $0.deadlineUUID == id })) { $0.snapshot }.first
    }

    private func accept(_ h: BookingHarness, at date: Date) async throws {
        let item = LoanReminders.returnReminder(bookingID: "b_789", title: "Return Synthetic camera kit", source: h.sourceID, at: date)
        _ = try await FeedDeadlineReconciler(stores: h.stores).upsert([item], now: h.clock.now())
    }

    @Test func acceptingANewSlotMovesTheReminder() async throws {
        let h = try BookingHarness()
        try await h.register()
        h.seed()
        try await h.sync.refresh(h.source)
        try await accept(h, at: utcDate(2026, 10, 28, 11))
        try await accept(h, at: utcDate(2026, 10, 28, 10))
        let all = try await h.stores.college.fetch(FetchDescriptor<Deadline>()) { $0.snapshot }
        #expect(all.count == 2) // the loan and one reminder
        #expect(try await reminder(h)?.dueAt == utcDate(2026, 10, 28, 10))
        #expect(try await reminder(h)?.origin == .booking)
    }

    @Test func reminderSurvivesAFullRefreshWhileTheLoanIsActive() async throws {
        let h = try BookingHarness(withAPIToken: false) // iCal: every refresh is a full snapshot
        try await h.register()
        h.seed()
        try await h.sync.refresh(h.source)
        try await accept(h, at: utcDate(2026, 10, 28, 11))
        h.clock.advance(by: 3600)
        h.server.put(.init(id: "b_793", title: "Synthetic extra", start: utcDate(2026, 10, 26, 10), due: utcDate(2026, 10, 29, 16), updatedAt: h.clock.now()))
        try await h.sync.refresh(h.source)
        #expect(try await reminder(h) != nil)
    }

    @Test func reminderGoesWhenTheLoanIsReturned() async throws {
        let h = try BookingHarness()
        try await h.register()
        h.seed()
        try await h.sync.refresh(h.source)
        try await accept(h, at: utcDate(2026, 10, 28, 11))
        h.clock.advance(by: 3600)
        h.server.put(.init(id: "b_789", status: "returned", title: "Synthetic camera kit", start: utcDate(2026, 10, 26, 10),
                           due: utcDate(2026, 10, 28, 16), returnedAt: h.clock.now(), updatedAt: h.clock.now()))
        try await h.sync.refresh(h.source)
        #expect(try await reminder(h) == nil)
    }

    @Test func reminderGoesOnDisconnect() async throws {
        let h = try BookingHarness()
        try await h.register()
        h.seed()
        try await h.sync.refresh(h.source)
        try await accept(h, at: utcDate(2026, 10, 28, 11))
        try await h.sync.disconnect(h.sourceID)
        #expect(try await reminder(h) == nil)
    }
}
