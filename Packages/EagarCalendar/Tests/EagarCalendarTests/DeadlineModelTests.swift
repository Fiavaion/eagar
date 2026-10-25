import EagarCore
import EagarStore
import Foundation
import SwiftData
import Testing
@testable import EagarCalendar

struct DeadlineModelTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    private func make(_ dc: DataClass) -> Deadline {
        Deadline(title: "Essay", dueAt: t0 + 86_400, dataClass: dc, createdAt: t0)
    }

    private func count(_ store: ClassifiedStore) async throws -> Int {
        try await store.perform { try $0.fetchCount(FetchDescriptor<Deadline>()) }
    }

    @Test func routesByClassAndRefusesMismatch() async throws {
        let stores = try EagarStores(location: .inMemory, models: [Deadline.self])
        try await stores.insert(make(.personal))
        try await stores.insert(make(.college))
        #expect(try await count(stores.personal) == 1)
        #expect(try await count(stores.college) == 1)

        await #expect(throws: StoreError.classMismatch(store: .personal, dataClass: .college)) {
            try await stores.personal.insert(make(.college))
        }
        await #expect(throws: StoreError.classMismatch(store: .college, dataClass: .personal)) {
            try await stores.college.insert(make(.personal))
        }
        #expect(try await count(stores.personal) == 1)
        #expect(try await count(stores.college) == 1)
    }

    @Test func defaultsAndRawFallbacks() {
        let d = make(.personal)
        #expect(d.reminderOffsetsMinutes == [1440, 120])
        #expect(d.status == .open)
        #expect(d.origin == .manual)
        #expect(d.sourceID == nil)
        d.dataClassRaw = "bogus"
        #expect(d.dataClass == .college)
        d.statusRaw = "bogus"
        d.originRaw = "bogus"
        #expect(d.status == .open)
        #expect(d.origin == .manual)
        let sid = SourceID()
        let s = Deadline(title: "x", dueAt: t0, origin: .canvas, dataClass: .college, sourceID: sid, createdAt: t0)
        #expect(s.sourceID == sid)
        #expect(s.origin == .canvas)
    }

    @Test func doneSnoozeReschedule() {
        let d = make(.personal)
        d.snooze(until: t0 + 3600)
        #expect(d.snoozedUntil == t0 + 3600)
        d.reschedule(to: t0 + 200_000)
        #expect(d.dueAt == t0 + 200_000)
        #expect(d.snoozedUntil == nil)
        d.snooze(until: t0 + 5)
        d.markDone(at: t0 + 10)
        #expect(d.status == .done)
        #expect(d.completedAt == t0 + 10)
        #expect(d.snoozedUntil == nil)
        #expect(d.snapshot.status == .done)
        #expect(d.snapshot.id == d.deadlineUUID)
    }

    @Test func overdueQuery() {
        let now = t0
        func s(_ offset: TimeInterval, status: DeadlineStatus = .open, snooze: Date? = nil) -> DeadlineSnapshot {
            DeadlineSnapshot(title: "\(offset)", dueAt: now + offset, dataClass: .personal, status: status, snoozedUntil: snooze)
        }
        let result = DeadlineQueries.overdue([
            s(-100), s(-5000), s(50), s(-10, status: .done), s(-20, snooze: now + 60), s(-30, snooze: now - 60),
        ], now: now)
        #expect(result.map(\.title) == ["-5000.0", "-100.0", "-30.0"])
    }
}
