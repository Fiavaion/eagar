import EagarCore
import Foundation

/// One charge expected in the summary month.
public struct UpcomingCharge: Sendable, Hashable {
    public let trialID: UUID
    public let service: String
    public let date: Date
    public let price: Decimal
    public let currencyCode: String
    /// The first charge after a free trial, rather than a routine renewal.
    public let endsTrial: Bool
    public let dataClass: DataClass
}

/// The monthly subscriptions summary the brief shows on the 1st (FR-TRIAL-06).
public struct MonthlySubscriptionSummary: Sendable, Hashable {
    /// The calendar month summarised (start inclusive, end exclusive).
    public let month: DateInterval
    /// Active subscriptions and trials counted.
    public let activeCount: Int
    /// What everything active costs per month if nothing is cancelled, per currency (no
    /// exchange rates), rounded to cents. Yearly plans count a twelfth, weekly 52/12.
    public let monthlyTotals: [String: Decimal]
    /// Charges falling inside `month`, earliest first.
    public let upcomingCharges: [UpcomingCharge]
    /// The sum of `upcomingCharges` per currency.
    public let upcomingTotals: [String: Decimal]
    /// The most restrictive class of the trials included (taint rule, BD-03).
    public let dataClass: DataClass
}

/// Builds ``MonthlySubscriptionSummary``. Pure: no clock, no store.
public enum SubscriptionSummary {
    /// Whether `date` is the day the brief carries the summary (the 1st of the month).
    public static func isSummaryDay(_ date: Date, calendar: Calendar = .current) -> Bool {
        calendar.component(.day, from: date) == 1
    }

    /// The summary for the calendar month containing `date`. Cancelled items are left out.
    public static func summary(_ trials: [TrialSnapshot], monthContaining date: Date, calendar: Calendar = .current) -> MonthlySubscriptionSummary {
        let month = calendar.dateInterval(of: .month, for: date) ?? DateInterval(start: date, duration: 0)
        let active = trials.filter { $0.status == .active }

        var monthly: [String: Decimal] = [:]
        var charges: [UpcomingCharge] = []
        for trial in active {
            monthly[trial.currencyCode, default: 0] += trial.price * trial.period.monthlyFactor
            for charge in TrialSchedule.charges(in: month, renewsAt: trial.renewsAt, period: trial.period, calendar: calendar) {
                charges.append(UpcomingCharge(
                    trialID: trial.id, service: trial.service, date: charge, price: trial.price,
                    currencyCode: trial.currencyCode, endsTrial: trial.isTrial && charge == trial.renewsAt,
                    dataClass: trial.dataClass
                ))
            }
        }
        charges.sort { ($0.date, $0.service) < ($1.date, $1.service) }
        let upcoming = charges.reduce(into: [String: Decimal]()) { $0[$1.currencyCode, default: 0] += $1.price }

        return MonthlySubscriptionSummary(
            month: month,
            activeCount: active.count,
            monthlyTotals: monthly.mapValues(roundedToCents),
            upcomingCharges: charges,
            upcomingTotals: upcoming.mapValues(roundedToCents),
            dataClass: Taint.derive(.subscriptionSummary, from: active.map(\.dataClass))
        )
    }

    static func roundedToCents(_ value: Decimal) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, 2, .plain)
        return result
    }
}
