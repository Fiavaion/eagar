import EagarCalendarTestSupport
import EagarCore
import Foundation
import Testing
@testable import EagarCalendar

struct DeadlineReminderMirrorTests {
    private func list(_ kind: CalendarSourceKind, id: String? = nil, modifiable: Bool = true, entity: CalendarEntity = .reminder) -> CalendarInfo {
        CalendarInfo(id: id ?? "L-\(kind.rawValue)", title: "List", accountTitle: "acct", sourceKind: kind, entity: entity, allowsModification: modifiable)
    }

    private func deadline(_ dc: DataClass, override: Bool = false) -> DeadlineSnapshot {
        DeadlineSnapshot(title: "Marking", dueAt: Date(timeIntervalSince1970: 1_800_000_000), dataClass: dc, mirrorOverride: override)
    }

    @Test(arguments: CalendarSourceKind.allCases, [true, false])
    func college(kind: CalendarSourceKind, inCollegeIDs: Bool) {
        for override in [true, false] {
            let l = list(kind)
            let ids: Set<String> = inCollegeIDs ? [l.id] : []
            let ok = !ReminderMirrorPolicy.eligibleLists(for: deadline(.college, override: override), among: [l], collegeListIDs: ids).isEmpty
            let expected: Bool = kind == .iCloud ? override : (kind == .local || inCollegeIDs)
            #expect(ok == expected, "\(kind) inCollegeIDs=\(inCollegeIDs) override=\(override)")
        }
    }

    @Test(arguments: CalendarSourceKind.allCases, [DataClass.personal, .publicContent, .approvedProfile])
    func personal(kind: CalendarSourceKind, dc: DataClass) {
        #expect(ReminderMirrorPolicy.eligibleLists(for: deadline(dc), among: [list(kind)], collegeListIDs: []).count == 1)
    }

    @Test func readOnlyAndEventCalendarsAreNeverEligible() {
        let lists = [list(.local, id: "ro", modifiable: false), list(.local, id: "ev", entity: .event), list(.local, id: "ok")]
        for dc in [DataClass.personal, .college] {
            #expect(ReminderMirrorPolicy.eligibleLists(for: deadline(dc), among: lists, collegeListIDs: []).map(\.id) == ["ok"])
        }
    }

    @Test func mirrorThrowsOnIneligible() async {
        let icloud = list(.iCloud)
        let store = FakeEventStore(calendars: [icloud])
        await #expect(throws: CalendarError.crossBoundaryWrite) {
            _ = try await ReminderMirror.mirror(deadline(.college), to: icloud, store: store)
        }
        #expect(store.state.withLock { $0.savedReminders.isEmpty })
    }

    @Test func mirrorSavesOnEligible() async throws {
        let local = list(.local)
        let store = FakeEventStore(calendars: [local])
        let d = deadline(.college)
        let id = try await ReminderMirror.mirror(d, to: local, store: store)
        let saved = store.state.withLock { $0.savedReminders }
        #expect(saved.count == 1)
        #expect(saved[0].listID == local.id)
        #expect(saved[0].draft.title == "Marking")
        #expect(saved[0].draft.due == d.dueAt)
        #expect(saved[0].id == id)
    }

    @Test func overriddenCollegeDeadlineMirrorsToICloud() async throws {
        let icloud = list(.iCloud)
        let store = FakeEventStore(calendars: [icloud])
        _ = try await ReminderMirror.mirror(deadline(.college, override: true), to: icloud, store: store)
        #expect(store.state.withLock { $0.savedReminders.count } == 1)
    }

    @Test func mirrorPropagatesStoreErrors() async {
        let local = list(.local)
        let store = FakeEventStore(calendars: [])
        await #expect(throws: CalendarError.calendarNotFound) {
            _ = try await ReminderMirror.mirror(deadline(.personal), to: local, store: store)
        }
    }
}
