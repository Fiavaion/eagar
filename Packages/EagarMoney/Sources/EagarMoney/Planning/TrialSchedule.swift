import Foundation

/// Date arithmetic for renewals and cancel-by dates (FR-TRIAL-01). Pure; every function takes
/// the calendar explicitly so time zone and DST behaviour is testable.
public enum TrialSchedule {
    /// Upper bound on charges walked when searching forward (a weekly plan for ~190 years).
    static let maxSteps = 10_000

    /// Cancel-by is the renewal minus the safety margin in **calendar days**, so the local
    /// time of day survives a DST change and month ends clamp (31 March − 30 days is
    /// 1 March, never a day that does not exist). Negative margins count as zero.
    public static func cancelBy(renewal: Date, safetyMarginDays: Int, calendar: Calendar) -> Date {
        let margin = max(0, safetyMarginDays)
        return calendar.date(byAdding: .day, value: -margin, to: renewal) ?? renewal
    }

    /// The `index`-th charge (0 is `renewsAt` itself). Always computed from the original
    /// date, so monthly charges on the 31st land on the last day of shorter months and
    /// return to the 31st afterwards instead of drifting.
    public static func charge(_ index: Int, renewsAt: Date, period: BillingPeriod, calendar: Calendar) -> Date? {
        guard index > 0 else { return renewsAt }
        let step = period.step
        return calendar.date(byAdding: step.component, value: step.value * index, to: renewsAt)
    }

    /// The first charge at or after `date`, or nil if none is found within ``maxSteps``.
    public static func renewal(onOrAfter date: Date, renewsAt: Date, period: BillingPeriod, calendar: Calendar) -> Date? {
        for index in 0 ..< maxSteps {
            guard let charge = charge(index, renewsAt: renewsAt, period: period, calendar: calendar) else { return nil }
            if charge >= date { return charge }
        }
        return nil
    }

    /// Every charge in `interval` (start inclusive, end exclusive).
    public static func charges(in interval: DateInterval, renewsAt: Date, period: BillingPeriod, calendar: Calendar) -> [Date] {
        var result: [Date] = []
        for index in 0 ..< maxSteps {
            guard let charge = charge(index, renewsAt: renewsAt, period: period, calendar: calendar),
                  charge < interval.end
            else { break }
            if charge >= interval.start { result.append(charge) }
        }
        return result
    }
}

/// The renewal Mark is currently racing, and the date he must cancel by to avoid it.
public struct CancelByTarget: Sendable, Hashable {
    public let renewal: Date
    public let cancelBy: Date
}

extension TrialSnapshot {
    /// Cancel-by for the stored renewal date (FR-TRIAL-01).
    public func cancelBy(calendar: Calendar = .current) -> Date {
        TrialSchedule.cancelBy(renewal: renewsAt, safetyMarginDays: safetyMarginDays, calendar: calendar)
    }

    /// The first renewal whose cancel-by day is today or later. For a trial this is the trial
    /// end; once that passes, a still-active subscription rolls on to its next renewal.
    /// `nil` once cancelled.
    public func nextCancelBy(now: Date, calendar: Calendar = .current) -> CancelByTarget? {
        guard status == .active else { return nil }
        let today = calendar.startOfDay(for: now)
        for index in 0 ..< TrialSchedule.maxSteps {
            guard let renewal = TrialSchedule.charge(index, renewsAt: renewsAt, period: period, calendar: calendar) else { return nil }
            let cancelBy = TrialSchedule.cancelBy(renewal: renewal, safetyMarginDays: safetyMarginDays, calendar: calendar)
            if calendar.startOfDay(for: cancelBy) >= today { return CancelByTarget(renewal: renewal, cancelBy: cancelBy) }
        }
        return nil
    }
}

/// Where the Cancel action goes (FR-TRIAL-05). Opening it never changes the status; Mark
/// confirms the cancellation separately.
public enum TrialCancelAction {
    /// Apple's subscription management page, the fallback for App Store subscriptions and for
    /// any service without a usable cancel URL.
    public static let appStoreSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!

    /// The service's cancel URL if it is a web (`https` or `http`) link with a host, else the
    /// App Store page. Other schemes are ignored so an imported string cannot launch an
    /// arbitrary app or script.
    public static func target(for trial: TrialSnapshot) -> URL {
        guard let url = trial.cancelURL,
              let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
              url.host() != nil
        else { return appStoreSubscriptionsURL }
        return url
    }
}
