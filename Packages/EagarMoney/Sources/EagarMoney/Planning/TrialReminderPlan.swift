import EagarCalendar
import EagarCore
import Foundation

/// A local notification the trial planner wants scheduled (FR-TRIAL-02). Mirrors
/// EagarCalendar's `PlannedNotification`, with the trial's identity instead of a deadline's.
public struct PlannedTrialReminder: Sendable, Hashable, Identifiable {
    public let id: String
    public let trialID: UUID
    /// Days before cancel-by; 0 is the day itself.
    public let daysBefore: Int
    public let fireDate: Date
    /// The cancel-by date this reminder counts down to.
    public let cancelBy: Date
    public let title: String
    public let body: String
    public let interruptionLevel: PlannedInterruptionLevel
    public let categoryIdentifier: String
    public let threadIdentifier: String
    /// Where the notification's Cancel action goes (FR-TRIAL-05).
    public let cancelTarget: URL
}

/// Pure planner from trial snapshots to reminders at 7, 3 and 1 days before cancel-by and on
/// the day (FR-TRIAL-02). The days are per trial (`reminderDays`), so they are configurable.
public enum TrialReminderPlan {
    public static let identifierPrefix = "trial."
    public static let categoryIdentifier = "trial"
    /// Opens ``TrialCancelAction/target(for:)``.
    public static let cancelActionIdentifier = "trial.cancel"
    /// Mark confirms he cancelled; the app then calls `Trial.confirmCancelled(at:)`.
    public static let confirmCancelledActionIdentifier = "trial.cancelled"
    /// Reminders fire at this local hour. Cancel-by is a day, not an instant: renewals are
    /// usually entered or imported as dates, so 09:00 is a sensible moment to act.
    public static let fireHour = 9
    /// Reminders this many days or fewer before cancel-by are time-sensitive (BD-21).
    public static let timeSensitiveMaxDays = 0

    public static func identifier(trialID: UUID, daysBefore: Int) -> String {
        "\(identifierPrefix)\(trialID.uuidString).\(daysBefore)"
    }

    /// Every reminder still in the future, for every active trial.
    /// `locale` formats the price and date in the notification body.
    public static func plan(
        _ trials: [TrialSnapshot], now: Date, calendar: Calendar = .current, locale: Locale = .current
    ) -> [PlannedTrialReminder] {
        trials.flatMap { plan(for: $0, now: now, calendar: calendar, locale: locale) }
    }

    static func plan(for trial: TrialSnapshot, now: Date, calendar: Calendar, locale: Locale) -> [PlannedTrialReminder] {
        guard let target = trial.nextCancelBy(now: now, calendar: calendar) else { return [] }
        let cancelDay = calendar.startOfDay(for: target.cancelBy)
        var seen = Set<Int>()
        return trial.reminderDays.sorted(by: >).compactMap { days in
            guard days >= 0, seen.insert(days).inserted,
                  let day = calendar.date(byAdding: .day, value: -days, to: cancelDay),
                  let fire = calendar.date(bySettingHour: fireHour, minute: 0, second: 0, of: day),
                  fire > now
            else { return nil }
            let (title, body) = content(for: trial, daysBefore: days, cancelBy: target.cancelBy, calendar: calendar, locale: locale)
            return PlannedTrialReminder(
                id: identifier(trialID: trial.id, daysBefore: days),
                trialID: trial.id,
                daysBefore: days,
                fireDate: fire,
                cancelBy: target.cancelBy,
                title: title,
                body: body,
                interruptionLevel: days <= timeSensitiveMaxDays ? .timeSensitive : .active,
                categoryIdentifier: categoryIdentifier,
                threadIdentifier: "trial.\(trial.id.uuidString)",
                cancelTarget: TrialCancelAction.target(for: trial)
            )
        }
    }

    /// Trials are personal. Should one ever carry the college class, its reminder is
    /// content-free, as college deadlines are (BD-04).
    static func content(
        for trial: TrialSnapshot, daysBefore: Int, cancelBy: Date, calendar: Calendar, locale: Locale
    ) -> (title: String, body: String) {
        guard trial.dataClass != .college else {
            return (
                String(localized: "Subscription reminder", bundle: .module),
                String(localized: "A subscription needs cancelling soon", bundle: .module)
            )
        }
        let price = trial.price.formatted(.currency(code: trial.currencyCode).locale(locale))
        if daysBefore == 0 {
            return (trial.service, String(localized: "Cancel today to avoid being charged \(price)", bundle: .module))
        }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale)
        style.timeZone = calendar.timeZone
        let day = cancelBy.formatted(style)
        return (trial.service, String(localized: "Cancel by \(day) to avoid being charged \(price)", bundle: .module))
    }
}
