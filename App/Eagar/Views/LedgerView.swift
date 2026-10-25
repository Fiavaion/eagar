import EagarCore
import EagarLedger
import SwiftUI
import UniformTypeIdentifiers

/// The privacy ledger viewer (FR-PRIV-05): summary header, filters, entries and exports.
struct LedgerView: View {
    let model: AppModel
    @State private var destination: String?
    @State private var dataClass: DataClass?
    @State private var limitDates = false
    @State private var from = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var to = Date()
    @State private var exportDocument: LedgerExportDocument?
    @State private var showingErase = false

    private var filtered: [LedgerRecord] {
        model.records.filter { record in
            (destination == nil || record.destination == destination)
                && (dataClass == nil || record.dataClass == dataClass)
                && (!limitDates || (record.at >= Calendar.current.startOfDay(for: from) && record.at <= endOfDay(to)))
        }
    }

    private var destinations: [String] {
        Array(Set(model.records.compactMap(\.destination))).sorted()
    }

    var body: some View {
        List {
            Section {
                if let summary = model.summary {
                    LedgerSummaryView(summary: summary)
                }
            }
            Section {
                Picker("Destination", selection: $destination) {
                    Text("All").tag(String?.none)
                    ForEach(destinations, id: \.self) { Text(verbatim: $0).tag(Optional($0)) }
                }
                Picker("Data class", selection: $dataClass) {
                    Text("All").tag(DataClass?.none)
                    ForEach(DataClass.allCases, id: \.self) { Text(DataClassLabel.name($0)).tag(Optional($0)) }
                }
                Toggle("Limit to dates", isOn: $limitDates)
                if limitDates {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("To", selection: $to, in: from..., displayedComponents: .date)
                }
            } header: {
                Text("Filter")
            }
            Section {
                if filtered.isEmpty {
                    Text("No entries yet. Every call to a model, and every blocked attempt, appears here.")
                        .foregroundStyle(.secondary)
                }
                ForEach(filtered) { record in
                    NavigationLink {
                        LedgerDetailView(record: record)
                    } label: {
                        LedgerRow(record: record)
                    }
                }
            } header: {
                Text("Entries")
            }
        }
        .navigationTitle(Text("Privacy ledger"))
        .refreshable { await model.refreshLedger() }
        .toolbar {
            ToolbarItem {
                Menu {
                    Button("Export as JSON, with payloads") { export(.json, payloads: true) }
                    Button("Export as JSON, without payloads") { export(.json, payloads: false) }
                    Button("Export as CSV, with payloads") { export(.csv, payloads: true) }
                    Button("Export as CSV, without payloads") { export(.csv, payloads: false) }
                    Divider()
                    Button("Erase older entries…", role: .destructive) { showingErase = true }
                } label: {
                    Label("Ledger actions", systemImage: "ellipsis.circle")
                }
            }
        }
        .fileExporter(
            isPresented: Binding(get: { exportDocument != nil }, set: { if !$0 { exportDocument = nil } }),
            document: exportDocument,
            contentType: exportDocument?.contentType ?? .json,
            defaultFilename: "eagar-privacy-ledger"
        ) { _ in }
        .sheet(isPresented: $showingErase) {
            EraseLedgerSheet(model: model)
        }
    }

    private func export(_ format: LedgerExport.FileFormat, payloads: Bool) {
        guard let data = model.exportLedger(filtered, as: format, includePayloads: payloads) else { return }
        exportDocument = LedgerExportDocument(data: data, contentType: format == .json ? .json : .commaSeparatedText)
    }

    private func endOfDay(_ date: Date) -> Date {
        Calendar.current.date(byAdding: DateComponents(day: 1, second: -1), to: Calendar.current.startOfDay(for: date)) ?? date
    }
}

struct LedgerSummaryView: View {
    let summary: LedgerSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text("Cloud calls carrying college content: \(summary.cloudCallsWithCollegeContent)")
            } icon: {
                Image(systemName: summary.cloudCallsWithCollegeContent == 0 ? "checkmark.shield" : "exclamationmark.shield")
            }
            .font(.headline)
            Text("Blocked attempts: \(summary.blockedAttempts)")
            Text("Calls that left your devices: \(summary.offDeviceCalls)")
            Text("Recorded cost: \(MicroUSD.text(summary.totalCostMicroUSD))")
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Cloud calls carrying college content: \(summary.cloudCallsWithCollegeContent). Blocked attempts: \(summary.blockedAttempts). Calls that left your devices: \(summary.offDeviceCalls). Recorded cost: \(MicroUSD.text(summary.totalCostMicroUSD))."))
        .accessibilityIdentifier("ledger.summary")
    }
}

private struct LedgerRow: View {
    let record: LedgerRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(LedgerLabels.kind(record.kind)).font(.headline)
                Spacer()
                Text(record.at, format: .dateTime.day().month().hour().minute())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if let tier = record.tier { TierBadge(tier: tier) }
                Text(DataClassLabel.name(record.dataClass))
                Text(LedgerLabels.outcome(record.outcome))
                if let cost = record.costMicroUSD { Text(MicroUSD.text(cost)) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

struct LedgerDetailView: View {
    let record: LedgerRecord

    var body: some View {
        List {
            Section {
                LabeledContent("Time") { Text(record.at, format: .dateTime) }
                LabeledContent("Event") { Text(LedgerLabels.kind(record.kind)) }
                LabeledContent("Outcome") { Text(LedgerLabels.outcome(record.outcome)) }
                if let tier = record.tier { LabeledContent("Processed") { TierBadge(tier: tier) } }
                if let destination = record.destination { LabeledContent("Destination") { Text(verbatim: destination) } }
                if let region = record.region { LabeledContent("Region") { Text(verbatim: region) } }
                if let modelID = record.modelID { LabeledContent("Model") { Text(verbatim: modelID) } }
                LabeledContent("Purpose") { Text(verbatim: record.purpose) }
                LabeledContent("Data class") { Text(DataClassLabel.name(record.dataClass)) }
                LabeledContent("Inputs") { Text(record.inputCount, format: .number) }
                if let detail = record.detail { LabeledContent("Detail") { Text(verbatim: detail) } }
            }
            Section {
                if let input = record.inputTokens { LabeledContent("Input tokens") { Text(input, format: .number) } }
                if let output = record.outputTokens { LabeledContent("Output tokens") { Text(output, format: .number) } }
                if let cost = record.costMicroUSD { LabeledContent("Cost") { Text(MicroUSD.text(cost)) } }
                if let ms = record.durationMilliseconds { LabeledContent("Duration") { Text(Duration.milliseconds(ms), format: .units(allowed: [.seconds, .milliseconds])) } }
            } header: {
                Text("Usage")
            }
            Section {
                if let payload = record.payload {
                    Text(verbatim: payload)
                        .font(.system(.footnote, design: .monospaced))
                        .textSelection(.enabled)
                } else if record.dataClass == .college {
                    Text("College entries record metadata only, never content.")
                } else {
                    Text("No payload was sent off this device.")
                }
            } header: {
                Text("Exact payload sent")
            }
        }
        .navigationTitle(Text(LedgerLabels.kind(record.kind)))
    }
}

private struct EraseLedgerSheet: View {
    let model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var cutoff = Calendar.current.date(byAdding: .month, value: -3, to: Date()) ?? Date()
    @State private var confirming = false

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Erase entries before", selection: $cutoff, in: ...Date(), displayedComponents: .date)
                Text("You will be asked to authenticate. The erasure itself is recorded in the ledger.")
                    .foregroundStyle(.secondary)
                Button("Erase", role: .destructive) { confirming = true }
            }
            .navigationTitle(Text("Erase older entries"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .confirmationDialog("Erase ledger entries?", isPresented: $confirming) {
                Button("Erase entries", role: .destructive) {
                    Task {
                        await model.eraseLedger(before: cutoff)
                        dismiss()
                    }
                }
            } message: {
                Text("This cannot be undone.")
            }
        }
    }
}

struct LedgerExportDocument: FileDocument {
    static let readableContentTypes: [UTType] = []
    static let writableContentTypes: [UTType] = [.json, .commaSeparatedText]

    let data: Data
    let contentType: UTType

    init(data: Data, contentType: UTType) {
        self.data = data
        self.contentType = contentType
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.featureUnsupported)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
