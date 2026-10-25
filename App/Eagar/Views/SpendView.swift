import EagarAI
import SwiftUI

/// Spend meter skeleton (FR-AI-09) and the model price table (FR-AI-08).
struct SpendView: View {
    let model: AppModel
    @State private var capText = ""

    var body: some View {
        Form {
            if let spend = model.spend {
                Section {
                    LabeledContent("Today") { Text(MicroUSD.text(spend.todayMicroUSD)) }
                    LabeledContent("This month") { Text(MicroUSD.text(spend.monthMicroUSD)) }
                    ForEach(spend.byPurposeMicroUSD.sorted { $0.key < $1.key }, id: \.key) { purpose, cost in
                        LabeledContent { Text(MicroUSD.text(cost)) } label: { Text(verbatim: purpose) }
                    }
                } header: {
                    Text("Claude spending")
                } footer: {
                    Text("Calculated from the token counts Claude reports and the price table below.")
                }
            }
            Section {
                TextField("Monthly limit in US dollars", text: $capText)
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                Button("Save limit") { model.setMonthlyCap(dollars: Decimal(string: capText)) }
                if model.isCapReached {
                    Label("The limit is reached. Claude features are paused until next month or until you raise the limit.", systemImage: "pause.circle")
                }
            } header: {
                Text("Soft monthly limit")
            } footer: {
                Text("Leave empty for no limit. Set a hard limit on the workspace in Claude Console as well.")
            }
            Section {
                ForEach(model.catalog.offeredModels) { entry in
                    VStack(alignment: .leading) {
                        Text(verbatim: entry.displayName).font(.headline)
                        if let price = entry.pricing.first {
                            Text("Input \(price.inputPerMTok.formatted(.currency(code: "USD"))) and output \(price.outputPerMTok.formatted(.currency(code: "USD"))) per million tokens")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Models")
            } footer: {
                Text("Prices checked on \(model.catalog.verifiedOn).")
            }
        }
        .navigationTitle(Text("Spending"))
        .onAppear {
            capText = model.monthlyCapMicroUSD.map { (Decimal($0) / 1_000_000).formatted() } ?? ""
        }
    }
}
