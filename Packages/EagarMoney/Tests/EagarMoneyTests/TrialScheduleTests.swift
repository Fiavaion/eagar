import Foundation
import Testing
@testable import EagarMoney

struct TrialScheduleTests {
    let cal = TestCalendars.dublin

    @Test func FR_TRIAL_01_cancelByIsRenewalMinusMargin() {
        let renewal = TestCalendars.date(2026, 11, 20, 10)
        let trial = TrialSnapshot(service: "x", price: 1, renewsAt: renewal)
        #expect(trial.cancelBy(calendar: cal) == TestCalendars.date(2026, 11, 18, 10))
        #expect(TrialSchedule.cancelBy(renewal: renewal, safetyMarginDays: 5, calendar: cal) == TestCalendars.date(2026, 11, 15, 10))
    }

    @Test func zeroAndNegativeMarginsMeanTheRenewalDay() {
        let renewal = TestCalendars.date(2026, 11, 20)
        #expect(TrialSchedule.cancelBy(renewal: renewal, safetyMarginDays: 0, calendar: cal) == renewal)
        #expect(TrialSchedule.cancelBy(renewal: renewal, safetyMarginDays: -3, calendar: cal) == renewal)
    }

    /// Irish summer time ends on 25 Oct 2026: 49 elapsed hours, but the same local time.
    @Test func FR_TRIAL_01_cancelByKeepsLocalTimeAcrossAutumnDST() {
        let renewal = TestCalendars.date(2026, 10, 26, 10)
        let cancelBy = TrialSchedule.cancelBy(renewal: renewal, safetyMarginDays: 2, calendar: cal)
        #expect(cancelBy == TestCalendars.date(2026, 10, 24, 10))
        #expect(renewal.timeIntervalSince(cancelBy) == 49 * 3600)
        #expect(cal.component(.hour, from: cancelBy) == 10)
    }

    /// Irish summer time starts on 29 Mar 2026.
    @Test func FR_TRIAL_01_cancelByKeepsLocalTimeAcrossSpringDST() {
        let renewal = TestCalendars.date(2026, 3, 30, 9)
        let cancelBy = TrialSchedule.cancelBy(renewal: renewal, safetyMarginDays: 2, calendar: cal)
        #expect(cancelBy == TestCalendars.date(2026, 3, 28, 9))
        #expect(renewal.timeIntervalSince(cancelBy) == 47 * 3600)
    }

    @Test func FR_TRIAL_01_cancelByCrossesMonthAndLeapDay() {
        #expect(TrialSchedule.cancelBy(renewal: TestCalendars.date(2027, 3, 1), safetyMarginDays: 2, calendar: cal) == TestCalendars.date(2027, 2, 27))
        #expect(TrialSchedule.cancelBy(renewal: TestCalendars.date(2028, 3, 1), safetyMarginDays: 2, calendar: cal) == TestCalendars.date(2028, 2, 28))
        #expect(TrialSchedule.cancelBy(renewal: TestCalendars.date(2027, 1, 1), safetyMarginDays: 2, calendar: cal) == TestCalendars.date(2026, 12, 30))
    }

    /// Midnight renewals in a zone whose DST change is at midnight would land on a missing
    /// hour; the calendar resolves them to a real instant on the right day.
    @Test func cancelByNeverLandsOnAMissingDay() {
        var santiago = Calendar(identifier: .gregorian)
        santiago.timeZone = TimeZone(identifier: "America/Santiago")!
        let renewal = TestCalendars.date(2026, 9, 8, in: santiago)
        let cancelBy = TrialSchedule.cancelBy(renewal: renewal, safetyMarginDays: 2, calendar: santiago)
        #expect(santiago.component(.day, from: cancelBy) == 6)
        #expect(santiago.component(.month, from: cancelBy) == 9)
    }

    @Test func monthlyChargesOnThe31stDoNotDrift() {
        let start = TestCalendars.date(2027, 1, 31, 8)
        let charges = (0 ... 3).compactMap { TrialSchedule.charge($0, renewsAt: start, period: .monthly, calendar: cal) }
        let days = charges.map { cal.component(.day, from: $0) }
        #expect(days == [31, 28, 31, 30])
        #expect(charges.allSatisfy { cal.component(.hour, from: $0) == 8 })
    }

    @Test func periodSteps() {
        let start = TestCalendars.date(2026, 11, 1)
        #expect(TrialSchedule.charge(1, renewsAt: start, period: .weekly, calendar: cal) == TestCalendars.date(2026, 11, 8))
        #expect(TrialSchedule.charge(1, renewsAt: start, period: .quarterly, calendar: cal) == TestCalendars.date(2027, 2, 1))
        #expect(TrialSchedule.charge(1, renewsAt: start, period: .yearly, calendar: cal) == TestCalendars.date(2027, 11, 1))
    }

    @Test func renewalOnOrAfter() {
        let start = TestCalendars.date(2026, 1, 15)
        #expect(TrialSchedule.renewal(onOrAfter: TestCalendars.date(2026, 10, 26), renewsAt: start, period: .monthly, calendar: cal) == TestCalendars.date(2026, 11, 15))
        #expect(TrialSchedule.renewal(onOrAfter: TestCalendars.date(2025, 1, 1), renewsAt: start, period: .monthly, calendar: cal) == start)
    }

    @Test func nextCancelByRollsOnForAnActiveSubscription() throws {
        let trial = TrialSnapshot(service: "x", price: 1, period: .monthly, renewsAt: TestCalendars.date(2026, 10, 10))
        let target = try #require(trial.nextCancelBy(now: TestCalendars.date(2026, 10, 26, 15), calendar: cal))
        #expect(target.renewal == TestCalendars.date(2026, 11, 10))
        #expect(target.cancelBy == TestCalendars.date(2026, 11, 8))
    }

    @Test func nextCancelByIncludesToday() throws {
        let trial = TrialSnapshot(service: "x", price: 1, renewsAt: TestCalendars.date(2026, 10, 28))
        let target = try #require(trial.nextCancelBy(now: TestCalendars.date(2026, 10, 26, 23), calendar: cal))
        #expect(target.cancelBy == TestCalendars.date(2026, 10, 26))
    }

    @Test func nextCancelByIsNilOnceCancelled() {
        let trial = TrialSnapshot(service: "x", price: 1, renewsAt: TestCalendars.date(2026, 12, 1), status: .cancelled)
        #expect(trial.nextCancelBy(now: TestCalendars.date(2026, 10, 26), calendar: cal) == nil)
    }

    // MARK: - Cancel action (FR-TRIAL-05)

    @Test func FR_TRIAL_05_cancelTargetPrefersTheServiceURL() {
        let url = URL(string: "https://www.example.com/account/cancel")!
        #expect(TrialCancelAction.target(for: TrialSnapshot(service: "x", price: 1, renewsAt: .now, cancelURL: url)) == url)
    }

    @Test(arguments: [nil, "javascript:alert(1)", "eagar://x", "file:///etc/hosts", "https://"])
    func FR_TRIAL_05_cancelTargetFallsBackToAppStore(raw: String?) {
        let trial = TrialSnapshot(service: "x", price: 1, renewsAt: .now, cancelURL: raw.flatMap(URL.init(string:)))
        #expect(TrialCancelAction.target(for: trial) == URL(string: "https://apps.apple.com/account/subscriptions")!)
    }
}
