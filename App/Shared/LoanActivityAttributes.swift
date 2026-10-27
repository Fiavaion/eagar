#if os(iOS)
import ActivityKit
import Foundation

/// The due-day loan Live Activity (FR-BOOK-07), shared by the app (which starts, updates and
/// ends it) and the widget extension (which draws it).
///
/// Loans are college data, so the activity carries counts and times only: no item names,
/// locations or booking IDs (BD-04, Lock Screen). Started locally; no push token (M5).
struct LoanActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        /// Active loans due back today, including any already overdue today.
        var loansDueToday: Int
        /// Of those, how many are past their due time.
        var overdueCount: Int
        /// The next due time today, or the latest one if all have passed.
        var nextDueAt: Date
    }

    /// `loans.YYYY-MM-DD`, one activity per local day. Content-free.
    var activityID: String
}
#endif
