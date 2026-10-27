import AppIntents
import EagarCalendar
import SwiftUI

@main
struct EagarApp: App {
    @State private var startup: Result<AppModel, StartupFailure>
    /// The notification centre holds its delegate weakly, so the app keeps it.
    @State private var notifications: NotificationResponder?

    init() {
        // `-EagarDemoData YES`: synthetic trials, people and a rich demo week in memory, for
        // screenshots (see DemoData); implies the three flags below.
        let demo = DemoData.isEnabled
        let inMemory = demo || UserDefaults.standard.bool(forKey: "EagarInMemoryStores")
        // `-EagarFakeCalendar YES`: synthetic calendars for UI tests and screenshots.
        let fakeCalendar = demo || UserDefaults.standard.bool(forKey: "EagarFakeCalendar")
        let eventStore: any EventStoreAdapting = fakeCalendar ? DemoEventStore(richWeek: demo) : EventKitAdapter()
        do {
            // Demo records never schedule real notifications, never touch the Keychain and never
            // reach the network: the feeds are served by a synthetic transport.
            let services = demo
                ? try AppServices.make(
                    inMemory: true, secrets: EphemeralSecretStore(), eventStore: eventStore, deadlineNotifications: DemoNotificationSink(),
                    briefNotifications: DemoNotificationSink(), trialReminders: DemoNotificationSink(),
                    birthdayNotifications: DemoNotificationSink(), feedTransport: DemoFeedTransport(),
                    loanActivities: SystemLoanActivityPresenter()
                )
                : try AppServices.make(inMemory: inMemory, eventStore: eventStore)
            // App Intents (Shortcuts, Siri) reach the same services (FR-OS-03).
            AppDependencyManager.shared.add(dependency: services)
            let model = AppModel(services: services)
            // Set before launch finishes, so a notification action that launched the app is
            // delivered (FR-OS-05).
            let responder = NotificationResponder(planner: model.planner, money: model.money)
            responder.install()
            _notifications = State(initialValue: responder)
            _startup = State(initialValue: .success(model))
        } catch {
            _notifications = State(initialValue: nil)
            _startup = State(initialValue: .failure(StartupFailure()))
        }
    }

    var body: some Scene {
        #if os(iOS)
        // FR-BOOK-02: the system wakes Eagar to refresh the college feeds.
        let model = try? startup.get()
        window.backgroundTask(.appRefresh(FeedRefreshSchedule.taskIdentifier)) {
            FeedRefreshSchedule.submit()
            await model?.backgroundRefresh()
        }
        #else
        window
        #endif
    }

    private var window: some Scene {
        WindowGroup {
            switch startup {
            case let .success(model):
                RootView(model: model)
            case .failure:
                ContentUnavailableView(
                    "Eagar could not open its data",
                    systemImage: "exclamationmark.triangle",
                    description: Text("The local stores could not be created. Restart Eagar; if this keeps happening, check free storage.")
                )
            }
        }
    }
}

struct StartupFailure: Error {}
