#if os(iOS)
import ActivityKit
import SwiftUI
import WidgetKit

/// The due-day loan Live Activity (FR-BOOK-07). Loans are college data: the Lock Screen and the
/// Dynamic Island show counts and times only, never an item name or location (BD-04).
struct LoanLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: LoanActivityAttributes.self) { context in
            LoanActivityLockScreenView(state: context.state)
                .padding()
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text("Loans due: \(context.state.loansDueToday)")
                    } icon: {
                        Image(systemName: "shippingbox")
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.nextDueAt, style: .time)
                        .accessibilityLabel(Text("Next due at \(context.state.nextDueAt, style: .time)"))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.overdueCount > 0 {
                        Text("Overdue: \(context.state.overdueCount)")
                    }
                }
            } compactLeading: {
                Image(systemName: "shippingbox")
                    .accessibilityLabel(Text("Loans due today"))
            } compactTrailing: {
                Text(context.state.nextDueAt, style: .time)
            } minimal: {
                Text(context.state.loansDueToday, format: .number)
                    .accessibilityLabel(Text("Loans due: \(context.state.loansDueToday)"))
            }
        }
    }
}

private struct LoanActivityLockScreenView: View {
    let state: LoanActivityAttributes.ContentState

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Loans due back today: \(state.loansDueToday)")
                    .font(.headline)
                Text("Next due at \(state.nextDueAt, style: .time)")
                    .font(.subheadline)
                if state.overdueCount > 0 {
                    Text("Overdue: \(state.overdueCount)")
                        .font(.subheadline)
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
#endif
