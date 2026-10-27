import EagarCore
import Foundation

/// What a due-day loan Live Activity shows (FR-BOOK-07). Times and counts only: no item
/// names, locations or booking IDs, so it is safe on the Lock Screen (BD-04).
public struct LoanActivityContent: Sendable, Hashable, Codable {
    /// Active loans due back today, including any already overdue today.
    public let loansDueToday: Int
    /// Of those, how many are past their due time.
    public let overdueCount: Int
    /// The earliest due time today that has not passed, or the latest one if all have.
    public let nextDueAt: Date

    public init(loansDueToday: Int, overdueCount: Int, nextDueAt: Date) {
        self.loansDueToday = loansDueToday
        self.overdueCount = overdueCount
        self.nextDueAt = nextDueAt
    }
}

/// A decision to show (or update) the due-day Live Activity.
public struct LoanActivityPlan: Sendable, Hashable {
    /// Stable per local day (`loans.YYYY-MM-DD`), so updates go to one activity. Content-free.
    public let activityID: String
    public let content: LoanActivityContent
    /// When the system may treat the content as stale: the next due time.
    public let staleDate: Date
    /// When to end the activity: the last due time today plus the grace period.
    public let endDate: Date
}

/// Decides whether a loan Live Activity should be running (FR-BOOK-07, local start in M2).
/// Pure; the widget extension renders the content, the app starts and ends the activity.
public enum LoanLiveActivityPlanner {
    /// How long after a due time the activity stays up.
    public static let defaultGrace: TimeInterval = 3600

    /// The activity for `now`, or nil when no active loan is due today (or all are past the grace).
    public static func plan(_ loans: [BookingSnapshot], now: Date, calendar: Calendar, grace: TimeInterval = defaultGrace) -> LoanActivityPlan? {
        let dues = loans
            .filter(\.booking.isActiveLoan)
            .compactMap(\.booking.due)
            .filter { calendar.isDate($0, inSameDayAs: now) }
            .sorted()
        guard let last = dues.last, now < last.addingTimeInterval(grace) else { return nil }
        let upcoming = dues.first { $0 >= now }
        let overdue = dues.filter { $0 < now }.count
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        let id = String(format: "loans.%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
        return LoanActivityPlan(
            activityID: id,
            content: LoanActivityContent(loansDueToday: dues.count, overdueCount: overdue, nextDueAt: upcoming ?? last),
            staleDate: upcoming ?? last.addingTimeInterval(grace),
            endDate: last.addingTimeInterval(grace)
        )
    }
}
