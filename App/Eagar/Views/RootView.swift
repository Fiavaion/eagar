import EventKit
import SwiftUI

enum RootTab: String, Hashable {
    case today, deadlines, settings, key, ledger, spending
}

struct RootView: View {
    let model: AppModel
    /// `-EagarInitialTab ledger` opens a given tab (UI tests, screenshots).
    @State private var tab = UserDefaults.standard.string(forKey: "EagarInitialTab").flatMap(RootTab.init(rawValue:)) ?? .today
    /// First run (FR-CORE-05). `-EagarSkipOnboarding YES` skips it for UI tests.
    @State private var showingOnboarding = !UserDefaults.standard.bool(forKey: OnboardingView.completedKey)
        && !UserDefaults.standard.bool(forKey: "EagarSkipOnboarding")
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let planner = model.planner
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max", value: RootTab.today) {
                NavigationStack { TodayView(planner: planner) }
            }
            Tab("Deadlines", systemImage: "flag", value: RootTab.deadlines) {
                NavigationStack { DeadlinesView(planner: planner) }
            }
            Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                NavigationStack { SettingsView(model: model) }
            }
            Tab("Privacy ledger", systemImage: "list.bullet.rectangle", value: RootTab.ledger) {
                NavigationStack { LedgerView(model: model) }
            }
            Tab("Claude key", systemImage: "key", value: RootTab.key) {
                NavigationStack { KeySetupView(model: model) }
            }
            Tab("Spending", systemImage: "chart.bar", value: RootTab.spending) {
                NavigationStack { SpendView(model: model) }
            }
        }
        .task {
            await model.refreshLedger()
            await model.startSync()
            await planner.appBecameActive()
        }
        .task { await model.watchKillSwitch() }
        .task {
            // Calendar edits made elsewhere while Eagar is open (FR-CAL-05). No Combine (CLAUDE.md).
            for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                await planner.refresh()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // Scene activation is the app-open breakpoint (FR-BRIEF-02).
            if phase == .active { Task { await planner.appBecameActive() } }
        }
        .sheet(isPresented: $showingOnboarding, onDismiss: completeOnboarding) {
            OnboardingView(planner: planner) { showingOnboarding = false }
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } }),
            presenting: model.failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { planner.failure != nil }, set: { if !$0 { planner.failure = nil } }),
            presenting: planner.failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: OnboardingView.completedKey)
    }
}
