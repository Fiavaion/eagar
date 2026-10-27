import EagarCore
import EagarMoney
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Trials and subscriptions (FR-TRIAL-01, 02, 03, 05, 06).
struct SubscriptionsView: View {
    let money: MoneyModel
    @State private var editing: TrialEditorDraft?
    @State private var photo: PhotosPickerItem?
    @State private var choosingPhoto = false
    @State private var importingFile = false
    @State private var confirmingCancel: TrialSnapshot?
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            if money.trials.isEmpty {
                ContentUnavailableView {
                    Label("No subscriptions", systemImage: "creditcard")
                } description: {
                    Text("Add a free trial or subscription and Eagar reminds you 7, 3 and 1 days before you need to cancel, and on the day.")
                } actions: {
                    Button("Add subscription") { editing = money.newDraft() }
                }
            } else {
                SummarySection(money: money)
            }
            if money.isImporting {
                Section {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("Reading the screenshot on this device…")
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            let active = money.activeTrials
            if !active.isEmpty {
                Section {
                    ForEach(active) { trial in
                        TrialRow(
                            money: money, trial: trial,
                            onEdit: { editing = money.editDraft(trial.id) },
                            onCancel: { startCancel(trial) }
                        )
                    }
                } header: {
                    Text("Active")
                }
            }
            let cancelled = money.cancelledTrials
            if !cancelled.isEmpty {
                Section {
                    ForEach(cancelled) { trial in
                        TrialRow(money: money, trial: trial, onEdit: { editing = money.editDraft(trial.id) }, onCancel: {})
                    }
                } header: {
                    Text("Cancelled")
                }
            }
        }
        .navigationTitle(Text("Subscriptions"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editing = money.newDraft()
                    } label: {
                        Label("Add manually", systemImage: "square.and.pencil")
                    }
                    .accessibilityIdentifier("subscriptions.addManual")
                    Button {
                        choosingPhoto = true
                    } label: {
                        Label("Import a screenshot", systemImage: "photo")
                    }
                    Button {
                        importingFile = true
                    } label: {
                        Label("Import an image file", systemImage: "doc")
                    }
                } label: {
                    Label("Add subscription", systemImage: "plus")
                }
                .accessibilityIdentifier("subscriptions.add")
            }
        }
        .photosPicker(isPresented: $choosingPhoto, selection: $photo, matching: .images)
        .onChange(of: photo) { _, item in
            guard let item else { return }
            photo = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await money.importImage(data)
                } else {
                    money.failure = .importFailed
                }
            }
        }
        .fileImporter(isPresented: $importingFile, allowedContentTypes: [.image]) { result in
            guard case let .success(url) = result else { return }
            Task { await importFile(url) }
        }
        .refreshable { await money.refresh() }
        .sheet(item: $editing) { TrialEditor(money: money, draft: $0) }
        .confirmationDialog(
            Text("Did you cancel \(confirmingCancel?.service ?? "")?"),
            isPresented: Binding(get: { confirmingCancel != nil }, set: { if !$0 { confirmingCancel = nil } }),
            titleVisibility: .visible,
            presenting: confirmingCancel
        ) { trial in
            Button("Yes, I cancelled it") { Task { await money.confirmCancelled(trial.id) } }
            Button("Not yet", role: .cancel) {}
        } message: { _ in
            Text("Eagar records a cancellation only when you confirm it.")
        }
    }

    /// Opens the cancel page, then asks Mark to confirm (FR-TRIAL-05).
    private func startCancel(_ trial: TrialSnapshot) {
        openURL(money.cancelTarget(trial.id))
        confirmingCancel = trial
    }

    private func importFile(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            await money.importImage(try Data(contentsOf: url))
        } catch {
            money.failure = .importFailed
        }
    }
}

/// Active count, monthly cost and this month's charges (FR-TRIAL-06).
private struct SummarySection: View {
    let money: MoneyModel

    var body: some View {
        let summary = money.summary
        Section {
            LabeledContent("Active") { Text(summary.activeCount, format: .number) }
            LabeledContent("Per month") { Text(MoneyText.totals(summary.monthlyTotals)) }
            LabeledContent("Charges this month") {
                if summary.upcomingCharges.isEmpty {
                    Text("None")
                } else {
                    Text("\(summary.upcomingCharges.count) · \(MoneyText.totals(summary.upcomingTotals))")
                }
            }
        } header: {
            Text("This month")
        } footer: {
            Text("Yearly plans count a twelfth per month. Totals are per currency, without exchange rates.")
        }
    }
}

enum MoneyText {
    /// "€45.97", or "€30.00 and £5.99" for several currencies.
    static func totals(_ totals: [String: Decimal]) -> String {
        guard !totals.isEmpty else { return Decimal(0).formatted(.currency(code: defaultTrialCurrencyCode)) }
        return totals.keys.sorted().map { totals[$0, default: 0].formatted(.currency(code: $0)) }.formatted(.list(type: .and))
    }

    static func price(_ trial: TrialSnapshot) -> String {
        trial.price.formatted(.currency(code: trial.currencyCode))
    }

    static func period(_ period: BillingPeriod) -> LocalizedStringResource {
        switch period {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .quarterly: "Every 3 months"
        case .yearly: "Yearly"
        }
    }
}

/// One trial with Cancel, edit and delete. Swipe actions have button equivalents in the menu.
private struct TrialRow: View {
    let money: MoneyModel
    let trial: TrialSnapshot
    let onEdit: () -> Void
    let onCancel: () -> Void

    private var isActive: Bool { trial.status == .active }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(trial.service)
                            .font(.body.weight(.medium))
                            .strikethrough(!isActive)
                        if trial.isTrial && isActive {
                            Text("Free trial")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .overlay(Capsule().strokeBorder(.secondary))
                        }
                    }
                    Text("\(MoneyText.price(trial)) · \(Text(MoneyText.period(trial.period)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if isActive, let cancelBy = money.nextCancelBy(trial) {
                        Text("Cancel by \(cancelBy, format: .dateTime.weekday(.wide).day().month())")
                            .font(.subheadline)
                    } else if let cancelledAt = trial.cancelledAt {
                        Text("Cancelled \(cancelledAt, format: .dateTime.day().month().year())")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Edit subscription"))

            if isActive {
                Button(action: onCancel) {
                    Text("Cancel…").frame(minHeight: 44)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel(Text("Open the cancel page for \(trial.service)"))
            }
            Menu {
                if isActive {
                    Button("Open the cancel page", action: onCancel)
                    Button("I've cancelled it") { Task { await money.confirmCancelled(trial.id) } }
                } else {
                    Button("Mark as active again") { Task { await money.reactivate(trial.id) } }
                }
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive) { Task { await money.delete(trial.id) } }
            } label: {
                Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("More actions for \(trial.service)"))
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { Task { await money.delete(trial.id) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("trial.row")
    }
}

/// Add, edit or confirm a trial (FR-TRIAL-01, FR-TRIAL-03).
struct TrialEditor: View {
    let money: MoneyModel
    @State private var draft: TrialEditorDraft
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar

    init(money: MoneyModel, draft: TrialEditorDraft) {
        self.money = money
        _draft = State(initialValue: draft)
    }

    static let currencies = ["EUR", "GBP", "USD"]
    static let reminderChoices = [14, 7, 3, 1, 0]

    var body: some View {
        NavigationStack {
            Form {
                if draft.isProposed {
                    Section {
                        Label {
                            Text("Proposed from your \(Text(sourceName)). Check every field before saving; nothing is stored until you do.")
                        } icon: {
                            Image(systemName: "text.viewfinder")
                        }
                        Text(methodText).font(.footnote).foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                Section {
                    TextField("Service", text: $draft.service)
                        .accessibilityIdentifier("trial.service")
                    HStack {
                        TextField("Price", value: $draft.price, format: .number.precision(.fractionLength(2)))
                            #if os(iOS)
                            .keyboardType(.decimalPad)
                            #endif
                            .accessibilityIdentifier("trial.price")
                        Picker("Currency", selection: $draft.currencyCode) {
                            ForEach(Self.currencies + (Self.currencies.contains(draft.currencyCode) ? [] : [draft.currencyCode]), id: \.self) {
                                Text(verbatim: $0).tag($0)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Picker("Billed", selection: $draft.period) {
                        ForEach(BillingPeriod.allCases, id: \.self) { Text(MoneyText.period($0)).tag($0) }
                    }
                    Toggle("Free trial", isOn: $draft.isTrial)
                }
                Section {
                    DatePicker("Started", selection: $draft.startedAt, displayedComponents: .date)
                    DatePicker(draft.isTrial ? "Trial ends" : "Renews", selection: $draft.renewsAt, displayedComponents: .date)
                    Stepper(value: $draft.safetyMarginDays, in: 0...14) {
                        Text("Safety margin: \(draft.safetyMarginDays) days")
                    }
                    LabeledContent("Cancel by") {
                        Text(draft.cancelBy(calendar: calendar), format: .dateTime.weekday(.wide).day().month())
                    }
                } header: {
                    Text("Dates")
                } footer: {
                    Text("Cancel-by is the renewal date minus the safety margin.")
                }
                Section {
                    TextField("Cancel page (optional)", text: $draft.cancelURLString)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    if !draft.cancelURLString.isEmpty && draft.cancelURL == nil {
                        Text("Use a web address starting with https://.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    Text("Cancelling")
                } footer: {
                    Text("Without a cancel page, Cancel opens your App Store subscriptions.")
                }
                Section {
                    ForEach(Self.reminderChoices, id: \.self) { days in
                        Toggle(isOn: Binding(
                            get: { draft.reminderDays.contains(days) },
                            set: { on in
                                if on { draft.reminderDays.insert(days) } else { draft.reminderDays.remove(days) }
                            }
                        )) {
                            Text(Self.reminderLabel(days))
                        }
                    }
                } header: {
                    Text("Remind me")
                }
                if !draft.isNew {
                    Section {
                        Button("Delete subscription", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(draft.isProposed ? "Discard" : "Cancel") {
                        if draft.isProposed { money.discardReview(draft) }
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await money.save(draft) {
                                if draft.isProposed { money.review = nil }
                                dismiss()
                            }
                        }
                    }
                    .disabled(!draft.canSave)
                    .accessibilityIdentifier("trial.save")
                }
            }
            .confirmationDialog("Delete this subscription?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let id = draft.id {
                        Task {
                            await money.delete(id)
                            dismiss()
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #endif
    }

    private var title: Text {
        if draft.isProposed { return Text("Confirm subscription") }
        return draft.isNew ? Text("New subscription") : Text("Edit subscription")
    }

    private var sourceName: LocalizedStringResource {
        if case .shared = draft.origin { return "shared item" }
        return "screenshot"
    }

    private var methodText: LocalizedStringResource {
        let method: TrialExtractionMethod = switch draft.origin {
        case .manual: .parser
        case let .screenshot(method), let .shared(_, method): method
        }
        return switch method {
        case .parser: "Read on this device with text recognition."
        case .onDeviceModel: "Read on this device with the on-device model."
        case .combined: "Read on this device with text recognition and the on-device model."
        }
    }

    static func reminderLabel(_ days: Int) -> LocalizedStringResource {
        switch days {
        case 0: "On the cancel-by day"
        case 1: "1 day before"
        default: "\(days) days before"
        }
    }
}
