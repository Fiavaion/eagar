import AppIntents
import EagarCalendar
import EagarCore
import Foundation
import WidgetKit

/// "Add a deadline" for Shortcuts and Siri (FR-OS-03). Always creates a **personal** deadline:
/// anything spoken or typed into Shortcuts is outside the college boundary's tooling, and a
/// college deadline is added in the app, where its class can be chosen.
struct AddDeadlineIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a deadline"
    static let description = IntentDescription("Adds a personal deadline to Eagar.")

    @Parameter(title: "Title")
    var title: String

    @Parameter(title: "Due")
    var due: Date

    @Dependency private var services: AppServices

    init() {}

    init(title: String, due: Date) {
        self.title = title
        self.due = due
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .result(dialog: "The deadline needs a title.") }
        try await services.stores.insert(Deadline(title: trimmed, dueAt: due, dataClass: .personal, createdAt: Date()))
        let rows = try await DeadlineRepository(stores: services.stores).all()
        await DeadlineNotificationSync.sync(deadlines: rows.map(\.snapshot), now: Date(), scheduler: services.deadlineNotifications)
        await services.sync?.syncLocalChanges()
        return .result(dialog: "Added.")
    }
}

/// "Show my brief" (FR-OS-03): opens Eagar on the Today tab, which is the default tab.
struct ShowBriefIntent: AppIntent {
    static let title: LocalizedStringResource = "Show my brief"
    static let description = IntentDescription("Opens Eagar's brief.")
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult { .result() }
}

struct EagarShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ShowBriefIntent(), phrases: ["Show my \(.applicationName) brief"], shortTitle: "Brief", systemImageName: "sun.horizon")
        AppShortcut(intent: AddDeadlineIntent(), phrases: ["Add a deadline in \(.applicationName)"], shortTitle: "Add deadline", systemImageName: "flag")
        AppShortcut(intent: SetKillSwitchIntent(value: true), phrases: ["Stop \(.applicationName) AI"], shortTitle: "Stop AI", systemImageName: "stop.circle")
    }
}

/// Donates intents so the system can suggest them. College items are never donated: Spotlight
/// and Siri suggestions are an egress path for college content (BD-04, B-7).
///
/// The planner must never call `donateAddedDeadline` for a college deadline; the system donor
/// refuses one anyway (defence in depth).
protocol IntentDonating: Sendable {
    func donateAddedDeadline(_ snapshot: DeadlineSnapshot)
    /// Withdraws earlier donations for a deadline, e.g. when it becomes college.
    func withdrawDonations(for deadlineID: UUID)
}

struct SystemIntentDonor: IntentDonating {
    func donateAddedDeadline(_ snapshot: DeadlineSnapshot) {
        guard snapshot.dataClass != .college else { return }
        let intent = AddDeadlineIntent(title: snapshot.title, due: snapshot.dueAt)
        Task { _ = try? await IntentDonationManager.shared.donate(intent: intent) }
    }

    /// Donations can't be deleted one by one, so every "Add a deadline" donation is withdrawn.
    /// Suggestions are rebuilt from later personal additions.
    func withdrawDonations(for deadlineID: UUID) {
        Task {
            do {
                try await IntentDonationManager.shared.deleteDonations(matching: .intentType(AddDeadlineIntent.self))
            } catch {
                EagarLog(.app).error("intent donations could not be withdrawn")
            }
        }
    }
}

/// Publishes the widget snapshot (FR-BRIEF-06). The snapshot holds no college titles.
protocol WidgetPublishing: Sendable {
    func publish(_ snapshot: WidgetSnapshot)
}

struct SystemWidgetPublisher: WidgetPublishing {
    func publish(_ snapshot: WidgetSnapshot) {
        do {
            try snapshot.save()
            WidgetCenter.shared.reloadAllTimelines()
        } catch {
            EagarLog(.app).error("widget snapshot could not be saved")
        }
    }
}
