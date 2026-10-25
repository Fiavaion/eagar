import EagarCalendarTestSupport
import Foundation
import Testing
@testable import EagarCalendar

struct DeadlineSyncTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let a = UUID()
    let b = UUID()

    private func snap(_ id: UUID, hours: Double, offsets: [Int] = [1440, 120]) -> DeadlineSnapshot {
        DeadlineSnapshot(id: id, title: "T", dueAt: now + hours * 3600, reminderOffsetsMinutes: offsets, dataClass: .personal)
    }

    @Test func addsMissingAndLeavesForeignAlone() async {
        let spy = SpyNotificationScheduler(foreignPending: ["other.thing"])
        await DeadlineNotificationSync.sync(deadlines: [snap(a, hours: 72)], now: now, scheduler: spy)
        let s = spy.state.withLock { $0 }
        #expect(s.added.count == 2)
        #expect(s.removed.isEmpty)
        #expect(s.foreignIdentifiers == ["other.thing"])
    }

    /// A second sync re-adds the same identifiers (replacing, so edits take effect) and removes nothing.
    @Test func secondSyncReplacesWithoutRemoving() async {
        let spy = SpyNotificationScheduler()
        let deadlines = [snap(a, hours: 72)]
        await DeadlineNotificationSync.sync(deadlines: deadlines, now: now, scheduler: spy)
        await DeadlineNotificationSync.sync(deadlines: deadlines, now: now, scheduler: spy)
        let s = spy.state.withLock { $0 }
        #expect(s.added.count == 4)
        #expect(Set(s.added.map(\.id)).count == 2)
        #expect(s.removed.isEmpty)
    }

    @Test func removesStaleOnlyWithPrefix() async {
        let spy = SpyNotificationScheduler(foreignPending: ["deadline.stale.60", "keep.me"])
        await DeadlineNotificationSync.sync(deadlines: [snap(b, hours: 72)], now: now, scheduler: spy)
        let s = spy.state.withLock { $0 }
        #expect(s.removed == ["deadline.stale.60"])
        #expect(s.foreignIdentifiers == ["keep.me"])
    }

    @Test func completedDeadlineIsRemoved() async {
        let spy = SpyNotificationScheduler()
        await DeadlineNotificationSync.sync(deadlines: [snap(a, hours: 72)], now: now, scheduler: spy)
        let done = DeadlineSnapshot(id: a, title: "T", dueAt: now + 72 * 3600, dataClass: .personal, status: .done)
        await DeadlineNotificationSync.sync(deadlines: [done], now: now, scheduler: spy)
        let s = spy.state.withLock { $0 }
        #expect(s.removed.count == 2)
        #expect(s.pending.isEmpty)
    }

    @Test func addFailureDoesNotStopTheRest() async {
        let spy = SpyNotificationScheduler()
        spy.state.withLock { $0.failAdd = true }
        await DeadlineNotificationSync.sync(deadlines: [snap(a, hours: 72)], now: now, scheduler: spy)
        #expect(spy.state.withLock { $0.pending.isEmpty })
    }

    @Test func spyAuthorisation() async throws {
        let spy = SpyNotificationScheduler()
        #expect(try await spy.requestAuthorization())
        #expect(spy.state.withLock { $0.authorizationRequests } == 1)
    }
}
