import EagarCalendar
import EagarCore
import Foundation
import Testing
@testable import EagarMoney

struct TrialReminderPlanTests {
    let cal = TestCalendars.dublin
    let locale = Locale(identifier: "en_IE")
    let now = TestCalendars.date(2026, 10, 1, 12)

    private func trial(renewal: Date, days: [Int] = defaultTrialReminderDays, dataClass: DataClass = .personal) -> TrialSnapshot {
        TrialSnapshot(service: "Spotify", price: Decimal(string: "11.99")!, renewsAt: renewal, reminderDays: days, dataClass: dataClass)
    }

    @Test func FR_TRIAL_02_remindersAt7_3_1_and0DaysAt9am() {
        // Renewal 22 Oct → cancel-by 20 Oct.
        let plan = TrialReminderPlan.plan([trial(renewal: TestCalendars.date(2026, 10, 22, 14))], now: now, calendar: cal, locale: locale)
        #expect(plan.map(\.daysBefore) == [7, 3, 1, 0])
        #expect(plan.map(\.fireDate) == [13, 17, 19, 20].map { TestCalendars.date(2026, 10, $0, 9) })
        #expect(plan.allSatisfy { $0.cancelBy == TestCalendars.date(2026, 10, 20, 14) })
    }

    @Test func FR_TRIAL_02_daysAreConfigurable() {
        let plan = TrialReminderPlan.plan([trial(renewal: TestCalendars.date(2026, 10, 22), days: [2, 14, 2, -1])], now: now, calendar: cal, locale: locale)
        #expect(plan.map(\.daysBefore) == [14, 2])
    }

    @Test func pastRemindersAreSkipped() {
        let late = TestCalendars.date(2026, 10, 19, 10)
        let plan = TrialReminderPlan.plan([trial(renewal: TestCalendars.date(2026, 10, 22))], now: late, calendar: cal, locale: locale)
        #expect(plan.map(\.daysBefore) == [0])
    }

    @Test func cancelledTrialsHaveNoReminders() {
        var cancelled = trial(renewal: TestCalendars.date(2026, 10, 22))
        cancelled.status = .cancelled
        #expect(TrialReminderPlan.plan([cancelled], now: now, calendar: cal).isEmpty)
    }

    /// The 7-day reminder is in summer time, the others after the change: all at 09:00 local.
    @Test func FR_TRIAL_02_remindersStayAt9AcrossDST() {
        let plan = TrialReminderPlan.plan([trial(renewal: TestCalendars.date(2026, 10, 30))], now: now, calendar: cal, locale: locale)
        #expect(plan.count == 4)
        #expect(plan.allSatisfy { cal.component(.hour, from: $0.fireDate) == 9 })
        #expect(plan.first?.fireDate == TestCalendars.date(2026, 10, 21, 9))
    }

    @Test func identifiersCategoryAndInterruption() throws {
        let t = trial(renewal: TestCalendars.date(2026, 10, 22))
        let plan = TrialReminderPlan.plan([t], now: now, calendar: cal, locale: locale)
        let first = try #require(plan.first)
        #expect(first.id == "trial.\(t.id.uuidString).7")
        #expect(first.categoryIdentifier == "trial")
        #expect(first.threadIdentifier == "trial.\(t.id.uuidString)")
        #expect(plan.map(\.interruptionLevel) == [.active, .active, .active, .timeSensitive])
        #expect(first.cancelTarget == TrialCancelAction.appStoreSubscriptionsURL)
    }

    @Test func personalContentNamesServiceAndPrice() throws {
        let plan = TrialReminderPlan.plan([trial(renewal: TestCalendars.date(2026, 10, 22))], now: now, calendar: cal, locale: locale)
        let first = try #require(plan.first)
        #expect(first.title == "Spotify")
        #expect(first.body.contains("11.99"))
        #expect(first.body.contains("20 Oct"))
        #expect(plan.last?.body.contains("today") == true)
    }

    @Test func Boundary_collegeTrialRemindersAreContentFree() {
        let plan = TrialReminderPlan.plan([trial(renewal: TestCalendars.date(2026, 10, 22), dataClass: .college)], now: now, calendar: cal, locale: locale)
        #expect(!plan.isEmpty)
        for reminder in plan {
            #expect(!reminder.title.contains("Spotify") && !reminder.body.contains("Spotify"))
            #expect(!reminder.body.contains("11.99"))
        }
    }

    @Test func rollsOnToTheNextRenewalAfterATrialConverts() {
        let t = TrialSnapshot(service: "x", price: 5, period: .monthly, renewsAt: TestCalendars.date(2026, 9, 15))
        let plan = TrialReminderPlan.plan([t], now: now, calendar: cal, locale: locale)
        #expect(plan.first?.cancelBy == TestCalendars.date(2026, 10, 13))
    }
}
