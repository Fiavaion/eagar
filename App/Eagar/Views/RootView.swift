import SwiftUI

enum RootTab: String, Hashable {
    case key, ledger, spending
}

struct RootView: View {
    let model: AppModel
    /// `-EagarInitialTab ledger` opens a given tab (UI tests, screenshots).
    @State private var tab = UserDefaults.standard.string(forKey: "EagarInitialTab").flatMap(RootTab.init(rawValue:)) ?? .key

    var body: some View {
        TabView(selection: $tab) {
            Tab("Claude key", systemImage: "key", value: RootTab.key) {
                NavigationStack { KeySetupView(model: model) }
            }
            Tab("Privacy ledger", systemImage: "list.bullet.rectangle", value: RootTab.ledger) {
                NavigationStack { LedgerView(model: model) }
            }
            Tab("Spending", systemImage: "chart.bar", value: RootTab.spending) {
                NavigationStack { SpendView(model: model) }
            }
        }
        .task { await model.refreshLedger() }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { model.failure != nil }, set: { if !$0 { model.failure = nil } }),
            presenting: model.failure
        ) { _ in
            Button("OK", role: .cancel) {}
        } message: { failure in
            Text(failure.message)
        }
    }
}
