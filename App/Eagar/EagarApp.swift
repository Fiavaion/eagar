import EagarCalendar
import SwiftUI

@main
struct EagarApp: App {
    @State private var startup: Result<AppModel, StartupFailure>

    init() {
        let inMemory = UserDefaults.standard.bool(forKey: "EagarInMemoryStores")
        // `-EagarFakeCalendar YES`: synthetic calendars for UI tests and screenshots.
        let eventStore: any EventStoreAdapting = UserDefaults.standard.bool(forKey: "EagarFakeCalendar") ? DemoEventStore() : EventKitAdapter()
        do {
            let services = try AppServices.make(inMemory: inMemory, eventStore: eventStore)
            _startup = State(initialValue: .success(AppModel(services: services)))
        } catch {
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
