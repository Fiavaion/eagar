import AppIntents
import EagarCalendar
import SwiftUI

@main
struct EagarApp: App {
    @State private var startup: Result<AppModel, StartupFailure>
    /// The notification centre holds its delegate weakly, so the app keeps it.
    @State private var notifications: NotificationResponder?

    init() {
        let inMemory = UserDefaults.standard.bool(forKey: "EagarInMemoryStores")
        // `-EagarFakeCalendar YES`: synthetic calendars for UI tests and screenshots.
        let eventStore: any EventStoreAdapting = UserDefaults.standard.bool(forKey: "EagarFakeCalendar") ? DemoEventStore() : EventKitAdapter()
        do {
            let services = try AppServices.make(inMemory: inMemory, eventStore: eventStore)
            // App Intents (Shortcuts, Siri) reach the same services (FR-OS-03).
            AppDependencyManager.shared.add(dependency: services)
            let model = AppModel(services: services)
            // Set before launch finishes, so a notification action that launched the app is
            // delivered (FR-OS-05).
            let responder = NotificationResponder(planner: model.planner)
            responder.install()
            _notifications = State(initialValue: responder)
            _startup = State(initialValue: .success(model))
        } catch {
            _notifications = State(initialValue: nil)
            _startup = State(initialValue: .failure(StartupFailure()))
        }
    }

    var body: some Scene {
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
