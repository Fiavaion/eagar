import EventKit
import SwiftUI

enum RootTab: String, Hashable {
    case today, deadlines, subscriptions, settings, key, ledger, spending
}

extension Notification.Name {
    /// Posted in the app process to switch tabs; `object` is the ``RootTab`` raw value (trial
    /// notifications, the brief's subscription summary).
    static let eagarShowTab = Notification.Name("app.eagar.showTab")
}

struct RootView: View {
    let model: AppModel
    /// `-EagarInitialTab ledger` opens a given tab (UI tests, screenshots).
    @State private var tab = UserDefaults.standard.string(forKey: "EagarInitialTab").flatMap(RootTab.init(rawValue:)) ?? .today
    /// First run (FR-CORE-05). `-EagarSkipOnboarding YES` skips it for UI tests.
    @State private var showingOnboarding = !UserDefaults.standard.bool(forKey: OnboardingView.completedKey)
        && !UserDefaults.standard.bool(forKey: "EagarSkipOnboarding")

    var body: some View {
        tabs
            .modifier(RootTasks(model: model, tab: $tab))
            .modifier(RootAlerts(model: model))
            .sheet(isPresented: $showingOnboarding, onDismiss: completeOnboarding) {
                OnboardingView(planner: model.planner) { showingOnboarding = false }
            }
    }

    private var tabs: some View {
        let planner = model.planner
        return TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max", value: RootTab.today) {
                NavigationStack { TodayView(model: model) }
            }
            Tab("Deadlines", systemImage: "flag", value: RootTab.deadlines) {
                NavigationStack { DeadlinesView(planner: planner, money: model.money) }
            }
            Tab("Subscriptions", systemImage: "creditcard", value: RootTab.subscriptions) {
                NavigationStack { SubscriptionsView(money: model.money) }
            }
            Tab("Settings", systemImage: "gearshape", value: RootTab.settings) {
                NavigationStack { SettingsView(model: model) }
            }
            TabSection("Privacy and AI") {
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
        }
        .tabViewStyle(.sidebarAdaptable)
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: OnboardingView.completedKey)
    }
}

/// Launch, activation and in-app navigation events.
private struct RootTasks: ViewModifier {
    let model: AppModel
    @Binding var tab: RootTab
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task {
                await model.refreshLedger()
                await model.startSync()
                await model.appBecameActive()
            }
            .task { await model.watchKillSwitch() }
            .task {
                // Calendar edits made elsewhere while Eagar is open (FR-CAL-05). No Combine (CLAUDE.md).
                for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
                    await model.refresh()
                }
            }
            .task {
                // The Control Centre "Start brief" control and brief notifications (FR-OS-02, FR-OS-05).
                for await _ in NotificationCenter.default.notifications(named: .eagarShowBrief) {
                    tab = .today
                }
            }
            .task {
                for await note in NotificationCenter.default.notifications(named: .eagarShowTab) {
                    if let raw = note.object as? String, let target = RootTab(rawValue: raw) { tab = target }
                }
            }
            .onChange(of: scenePhase) { _, phase in
                // Scene activation is the app-open breakpoint (FR-BRIEF-02).
                if phase == .active { Task { await model.appBecameActive() } }
            }
            // A proposed trial from a screenshot or the share extension, wherever Mark is (FR-TRIAL-03).
            .sheet(item: Binding(get: { model.money.review }, set: { if $0 == nil { model.money.review = nil } })) { draft in
                TrialEditor(money: model.money, draft: draft)
            }
    }
}

/// A failure whose message can be shown in an alert.
protocol UserFacingFailure: Identifiable, Equatable {
    var message: LocalizedStringResource { get }
}

extension AppFailure: UserFacingFailure {}
extension PlannerFailure: UserFacingFailure {}
extension MoneyFailure: UserFacingFailure {}

/// One "Something went wrong" alert per model.
private struct RootAlerts: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        let planner = model.planner
        let money = model.money
        content
            .failureAlert(Binding(get: { model.failure }, set: { model.failure = $0 }))
            .failureAlert(Binding(get: { planner.failure }, set: { planner.failure = $0 }))
            .failureAlert(Binding(get: { money.failure }, set: { money.failure = $0 }))
    }
}

extension View {
    func failureAlert<F: UserFacingFailure>(_ failure: Binding<F?>) -> some View {
        alert(
            "Something went wrong",
            isPresented: Binding(get: { failure.wrappedValue != nil }, set: { if !$0 { failure.wrappedValue = nil } }),
            presenting: failure.wrappedValue
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
    }
}
