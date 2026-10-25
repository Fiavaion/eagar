import SwiftUI

struct RootView: View {
    let model: AppModel

    var body: some View {
        TabView {
            Tab("Claude key", systemImage: "key") {
                NavigationStack { KeySetupView(model: model) }
            }
            Tab("Privacy ledger", systemImage: "list.bullet.rectangle") {
                NavigationStack { LedgerView(model: model) }
            }
            Tab("Spending", systemImage: "chart.bar") {
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
