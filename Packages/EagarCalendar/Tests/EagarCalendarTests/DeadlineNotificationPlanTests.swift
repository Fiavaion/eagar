import UserNotifications
import EagarCore
import Foundation
import Testing
@testable import EagarCalendar

private let dublin: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "Europe/Dublin")!
    return c
}()

private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
    dublin.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

struct DeadlineNotificationPlanTests {
    let now = date(2026, 11, 1, 8)
    let id = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!

    private func snapshot(
        due: Date? = nil, offsets: [Int] = [1440, 120], dataClass: DataClass = .personal,
        status: DeadlineStatus = .open, snoozedUntil: Date? = nil, allDay: Bool = false, title: String = "Hand in portfolio"
    ) -> DeadlineSnapshot {
        DeadlineSnapshot(
            id: id, title: title, dueAt: due ?? date(2026, 11, 10, 17), isAllDay: allDay, reminderOffsetsMinutes: offsets,
            dataClass: dataClass, status: status, snoozedUntil: snoozedUntil
        )
    }

    private func plan(_ s: DeadlineSnapshot, now: Date? = nil) -> [PlannedNotification] {
        DeadlineNotificationPlan.plan([s], now: now ?? self.now, calendar: dublin)
    }

    @Test func offsetsProduceIdentifiersAndFireDates() {
        let p = plan(snapshot())
        #expect(p.map(\.id) == ["deadline.\(id.uuidString).1440", "deadline.\(id.uuidString).120"])
        #expect(p.map(\.fireDate) == [date(2026, 11, 9, 17), date(2026, 11, 10, 15)])
        #expect(Set(p.map(\.threadIdentifier)).count == 1)
        #expect(p.allSatisfy { $0.categoryIdentifier == "deadline" })
        #expect(p[0].title == "Hand in portfolio")
        #expect(!p[0].body.isEmpty)
    }

    @Test func pastOffsetsAreSkipped() {
        let p = plan(snapshot(due: date(2026, 11, 1, 20)))
        #expect(p.map(\.offsetMinutes) == [120])
        #expect(plan(snapshot(due: date(2026, 10, 30))).isEmpty)
    }

    @Test func doneAndSnoozedAreSkipped() {
        #expect(plan(snapshot(status: .done)).isEmpty)
        // Snoozed past both offsets: only the reminder at the end of the snooze remains.
        let both = plan(snapshot(snoozedUntil: date(2026, 11, 10, 16)))
        #expect(both.count == 1)
        #expect(both.first?.id.hasSuffix(".snooze") == true)
        #expect(both.first?.fireDate == date(2026, 11, 10, 16))
        // Snoozed past the 1-day offset only: the 2-hour offset plus the snooze-end reminder.
        let partial = plan(snapshot(snoozedUntil: date(2026, 11, 10, 12)))
        #expect(partial.filter { !$0.id.hasSuffix(".snooze") }.map(\.offsetMinutes) == [120])
        #expect(partial.filter { $0.id.hasSuffix(".snooze") }.map(\.fireDate) == [date(2026, 11, 10, 12)])
    }

    @Test func interruptionLevels() {
        let p = plan(snapshot(offsets: [1440, 120, 30, 0]))
        let levels = Dictionary(uniqueKeysWithValues: p.map { ($0.offsetMinutes, $0.interruptionLevel) })
        #expect(levels[1440] == .active)
        #expect(levels[120] == .timeSensitive)
        #expect(levels[30] == .timeSensitive)
        #expect(levels[0] == .timeSensitive)
    }

    @Test func invalidAndDuplicateOffsetsAreIgnored() {
        #expect(plan(snapshot(offsets: [-5, 120, 120])).map(\.offsetMinutes) == [120])
    }

    @Test func Boundary_B9pre_collegeDeadlineNotificationIsContentFree() {
        let title = "Zephyrine moderation panel"
        let p = plan(snapshot(offsets: [1440, 120, 0], dataClass: .college, title: title))
        #expect(p.count == 3)
        for n in p {
            #expect(!n.title.localizedCaseInsensitiveContains(title))
            #expect(!n.body.localizedCaseInsensitiveContains(title))
            #expect(!n.title.localizedCaseInsensitiveContains("Zephyrine"))
            #expect(!n.body.localizedCaseInsensitiveContains("Zephyrine"))
            #expect(n.title == "College deadline")
        }
    }

    @Test func personalZeroOffsetBody() {
        let p = plan(snapshot(offsets: [0]))
        #expect(p.count == 1)
        #expect(p[0].fireDate == date(2026, 11, 10, 17))
    }

    @Test func allDayFiresAtNineLocal() {
        let due = date(2026, 11, 10)
        let p = plan(snapshot(due: due, offsets: [2880, 1440, 120], allDay: true))
        #expect(p.map(\.offsetMinutes) == [2880, 1440, 120])
        #expect(p[0].fireDate == date(2026, 11, 8, 9))
        #expect(p[1].fireDate == date(2026, 11, 9, 9))
        #expect(p[2].fireDate == date(2026, 11, 9, 22))
    }

    @Test func irelandDSTKeepsLocalTime() {
        // Clocks go back at 02:00 on Sunday 25 Oct 2026, so 10:00 that day is 25 elapsed hours
        // after 10:00 on 24 Oct (IST).
        let due = date(2026, 10, 25, 10)
        let p = plan(snapshot(due: due, offsets: [1440]), now: date(2026, 10, 20))
        #expect(p[0].fireDate == date(2026, 10, 24, 10))
        #expect(due.timeIntervalSince(p[0].fireDate) == 25 * 3600)
        // 26 Oct 10:00 minus a day is 25 Oct 10:00, both GMT: 24 elapsed hours.
        let after = plan(snapshot(due: date(2026, 10, 26, 10), offsets: [1440]), now: date(2026, 10, 20))
        #expect(after[0].fireDate == date(2026, 10, 25, 10))
    }

    @Test func requestMapping() throws {
        let p = plan(snapshot())
        let req = UserNotificationScheduler.request(for: p[1], calendar: dublin)
        #expect(req.identifier == p[1].id)
        #expect(req.content.title == "Hand in portfolio")
        #expect(req.content.categoryIdentifier == "deadline")
        #expect(req.content.threadIdentifier == p[1].threadIdentifier)
        #expect(req.content.interruptionLevel == .timeSensitive)
        let trigger = try #require(req.trigger as? UNCalendarNotificationTrigger)
        #expect(!trigger.repeats)
        #expect(trigger.dateComponents.hour == 15)
        #expect(trigger.dateComponents.day == 10)
        let active = UserNotificationScheduler.request(for: p[0], calendar: dublin)
        #expect(active.content.interruptionLevel == .active)
    }

    @Test func categoryHasDoneAndSnooze() {
        let c = UserNotificationScheduler.category()
        #expect(c.identifier == "deadline")
        #expect(c.actions.map(\.identifier) == ["deadline.done", "deadline.snooze"])
    }
}
