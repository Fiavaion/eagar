import EagarBookings
import EagarCore
import Foundation
#if os(iOS)
import ActivityKit
#endif

/// Starts, updates and ends the due-day loan Live Activity (FR-BOOK-07, local start only).
protocol LoanActivityPresenting: Sendable {
    /// Shows `plan`, or ends every loan activity when it is nil.
    func show(_ plan: LoanActivityPlan?) async
}

/// Tests, previews and macOS: no Live Activity.
struct NoLoanActivities: LoanActivityPresenting {
    func show(_ plan: LoanActivityPlan?) async {}
}

/// ActivityKit on iOS; nothing on macOS. The content is counts and times only (BD-04).
struct SystemLoanActivityPresenter: LoanActivityPresenting {
    func show(_ plan: LoanActivityPlan?) async {
        #if os(iOS)
        let running = Activity<LoanActivityAttributes>.activities
        // Yesterday's activity, or today's once no loan is due: end it.
        for activity in running where activity.attributes.activityID != plan?.activityID {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        guard let plan else { return }
        let state = LoanActivityAttributes.ContentState(
            loansDueToday: plan.content.loansDueToday, overdueCount: plan.content.overdueCount, nextDueAt: plan.content.nextDueAt
        )
        let content = ActivityContent(state: state, staleDate: plan.staleDate)
        if let current = running.first(where: { $0.attributes.activityID == plan.activityID }) {
            await current.update(content)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        do {
            _ = try Activity.request(attributes: LoanActivityAttributes(activityID: plan.activityID), content: content, pushType: nil)
        } catch {
            EagarLog(.feeds).notice("loan live activity not started")
        }
        #endif
    }
}
