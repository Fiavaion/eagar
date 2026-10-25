import SwiftUI

@main
struct EagarApp: App {
    @State private var startup: Result<AppModel, StartupFailure>

    init() {
        let inMemory = UserDefaults.standard.bool(forKey: "EagarInMemoryStores")
        do {
            _startup = State(initialValue: .success(AppModel(services: try AppServices.make(inMemory: inMemory))))
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
