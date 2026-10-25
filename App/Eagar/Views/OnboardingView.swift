import EagarBrief
import EagarCalendar
import SwiftUI

/// First run (FR-CORE-05): welcome, calendar access, confirm tags, first brief. Every step has
/// a default and the whole flow can be skipped.
struct OnboardingView: View {
    let planner: PlannerModel
    let onFinish: () -> Void

    private enum Step { case welcome, calendars, tags, brief }
    @State private var step = Step.welcome

    static let completedKey = "onboarding.completed"

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    content
                }
                .frame(maxWidth: 560, alignment: .leading)
                .padding()
                .frame(maxWidth: .infinity)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip", action: onFinish)
                        .accessibilityIdentifier("onboarding.skip")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 520)
        #endif
    }

    @ViewBuilder private var content: some View {
        switch step {
        case .welcome:
            Text("Welcome to Eagar")
                .font(.largeTitle.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Eagar gathers your calendars and deadlines into one brief, delivered at a natural break in your day.")
            Label("College data stays on your devices.", systemImage: "house.fill")
            Label("You choose what, if anything, goes to Claude.", systemImage: "cloud")
            Label("Every call off this device is in the privacy ledger.", systemImage: "list.bullet.rectangle")
            Text("Setup takes a couple of minutes.")
                .foregroundStyle(.secondary)
            primary("Get started") { step = .calendars }
        case .calendars:
            CalendarAccessExplanation(planner: planner)
            if planner.access == .fullAccess {
                primary("Continue") { step = .tags }
            } else {
                Button("Not now") { step = .brief }
                    .frame(minHeight: 44)
            }
        case .tags:
            Text("Check your calendars")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Eagar proposes college for calendars on an ncad.ie account and personal for the rest. Change any that are wrong.")
            ForEach(planner.eventCalendars) { calendar in
                CalendarTagRow(planner: planner, calendar: calendar, showsBriefToggle: false)
                Divider()
            }
            if planner.isCollegeCalendarMissing {
                MissingCollegeCalendarSteps()
            }
            primary("Confirm tags") {
                Task {
                    await planner.confirmProposedTags()
                    step = .brief
                }
            }
        case .brief:
            Text("Your first brief")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            if let brief = planner.brief, !brief.isEmpty {
                ForEach(brief.sections) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(BriefLabels.section(section.kind)).font(.headline)
                        ForEach(section.items) { item in
                            HStack {
                                Text(item.title)
                                Spacer()
                                if item.dataClass == .college { BoundaryBadge() }
                            }
                        }
                    }
                }
            } else {
                Text("Nothing needs you right now. Your brief fills up as you add deadlines and events.")
            }
            Text("Your morning brief arrives after 08:00, at the first natural break. You can change the times in Settings.")
                .foregroundStyle(.secondary)
            Button("Notify me when my brief is ready") {
                Task { await planner.requestNotificationAuthorisation() }
            }
            .frame(minHeight: 44)
            primary("Start using Eagar", action: onFinish)
        }
    }

    private func primary(_ title: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.borderedProminent)
        .accessibilityIdentifier("onboarding.next")
    }
}
