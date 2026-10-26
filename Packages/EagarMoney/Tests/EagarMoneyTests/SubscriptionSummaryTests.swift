import EagarCalendar
import EagarCore
import Foundation
import Testing
@testable import EagarMoney

struct SubscriptionSummaryTests {
    let cal = TestCalendars.dublin
    let first = TestCalendars.date(2026, 11, 1, 8)

    private func d(_ s: String) -> Decimal { Decimal(string: s)! }

    @Test func FR_TRIAL_06_monthlyTotalNormalisesPeriods() {
        let trials = [
            TrialSnapshot(service: "Monthly", price: d("10.00"), period: .monthly, renewsAt: TestCalendars.date(2026, 11, 5)),
            TrialSnapshot(service: "Yearly", price: d("120.00"), period: .yearly, renewsAt: TestCalendars.date(2027, 3, 1)),
            TrialSnapshot(service: "Quarterly", price: d("30.00"), period: .quarterly, renewsAt: TestCalendars.date(2027, 1, 1)),
            TrialSnapshot(service: "Weekly", price: d("3.00"), period: .weekly, renewsAt: TestCalendars.date(2026, 11, 2)),
        ]
        let summary = SubscriptionSummary.summary(trials, monthContaining: first, calendar: cal)
        // 10 + 10 + 10 + 3 × 52 / 12 (= 13)
        #expect(summary.monthlyTotals == ["EUR": d("43.00")])
        #expect(summary.activeCount == 4)
    }

    @Test func FR_TRIAL_06_currenciesStaySeparateAndCancelledIsExcluded() {
        let trials = [
            TrialSnapshot(service: "A", price: d("8.99"), currencyCode: "GBP", renewsAt: TestCalendars.date(2026, 11, 3)),
            TrialSnapshot(service: "B", price: d("9.99"), renewsAt: TestCalendars.date(2026, 11, 4)),
            TrialSnapshot(service: "C", price: d("99"), renewsAt: TestCalendars.date(2026, 11, 4), status: .cancelled),
        ]
        let summary = SubscriptionSummary.summary(trials, monthContaining: first, calendar: cal)
        #expect(summary.monthlyTotals == ["GBP": d("8.99"), "EUR": d("9.99")])
        #expect(summary.upcomingCharges.map(\.service) == ["A", "B"])
        #expect(summary.activeCount == 2)
    }

    @Test func FR_TRIAL_06_upcomingChargesInTheMonth() {
        let trials = [
            TrialSnapshot(service: "Weekly", price: d("2.50"), period: .weekly, isTrial: false, renewsAt: TestCalendars.date(2026, 10, 28)),
            TrialSnapshot(service: "Trial", price: d("11.99"), isTrial: true, renewsAt: TestCalendars.date(2026, 11, 20)),
            TrialSnapshot(service: "Later", price: d("50"), period: .yearly, renewsAt: TestCalendars.date(2027, 6, 1)),
            TrialSnapshot(service: "Earlier", price: d("5"), period: .monthly, isTrial: false, renewsAt: TestCalendars.date(2026, 8, 30)),
        ]
        let summary = SubscriptionSummary.summary(trials, monthContaining: first, calendar: cal)
        let weekly = summary.upcomingCharges.filter { $0.service == "Weekly" }.map(\.date)
        #expect(weekly == [4, 11, 18, 25].map { TestCalendars.date(2026, 11, $0) })
        let trial = summary.upcomingCharges.first { $0.service == "Trial" }
        #expect(trial?.endsTrial == true)
        #expect(summary.upcomingCharges.contains { $0.service == "Earlier" && $0.date == TestCalendars.date(2026, 11, 30) })
        #expect(!summary.upcomingCharges.contains { $0.service == "Later" })
        #expect(summary.upcomingTotals == ["EUR": d("10.00") + d("11.99") + d("5")])
        #expect(summary.upcomingCharges.map(\.date) == summary.upcomingCharges.map(\.date).sorted())
        #expect(summary.month.start == TestCalendars.date(2026, 11, 1))
        #expect(summary.month.end == TestCalendars.date(2026, 12, 1))
    }

    @Test func summaryDayIsTheFirst() {
        #expect(SubscriptionSummary.isSummaryDay(first, calendar: cal))
        #expect(!SubscriptionSummary.isSummaryDay(TestCalendars.date(2026, 11, 2), calendar: cal))
    }

    @Test func summaryClassFollowsTheTaintRule() {
        let personal = TrialSnapshot(service: "A", price: 1, renewsAt: first)
        #expect(SubscriptionSummary.summary([personal], monthContaining: first, calendar: cal).dataClass == .personal)
        let college = TrialSnapshot(service: "B", price: 1, renewsAt: first, dataClass: .college)
        #expect(SubscriptionSummary.summary([personal, college], monthContaining: first, calendar: cal).dataClass == .college)
        #expect(SubscriptionSummary.summary([], monthContaining: first, calendar: cal).dataClass == .publicContent)
    }

    // MARK: - Deadline mapping (FR-DL-01)

    @Test func FR_DL_01_trialCancelByBecomesATrialDeadline() throws {
        let trial = TrialSnapshot(service: "Netflix", price: d("10.99"), renewsAt: TestCalendars.date(2026, 11, 12, 15))
        let deadline = try #require(TrialDeadlineMapping.snapshot(for: trial, now: TestCalendars.date(2026, 10, 26), calendar: cal))
        #expect(deadline.id == trial.id)
        #expect(deadline.origin == .trial)
        #expect(deadline.dueAt == TestCalendars.date(2026, 11, 10))
        #expect(deadline.isAllDay)
        #expect(deadline.reminderOffsetsMinutes.isEmpty)
        #expect(deadline.dataClass == .personal)
        #expect(deadline.status == .open)
        #expect(deadline.title.contains("Netflix"))
    }

    @Test func FR_DL_01_cancelledTrialDeadlineIsDone() throws {
        let trial = TrialSnapshot(service: "x", price: 1, renewsAt: TestCalendars.date(2026, 11, 12), status: .cancelled, cancelledAt: first)
        let model = try #require(TrialDeadlineMapping.makeDeadline(for: trial, now: first, calendar: cal, createdAt: first))
        #expect(model.status == .done)
        #expect(model.origin == .trial)
        #expect(model.completedAt == first)
        #expect(model.deadlineUUID == trial.id)
    }
}
