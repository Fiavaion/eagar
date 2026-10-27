import EagarBookings
import EagarCalendar
import EagarCore
import EagarMoney
import SwiftUI

/// Deadlines, overdue first (FR-DL-01..04), with trial cancel-by days (origin `trial`), loan
/// returns (origin `booking`, with clash proposals, FR-BOOK-04) and Canvas assignments.
struct DeadlinesView: View {
    let planner: PlannerModel
    let money: MoneyModel
    let feeds: FeedsModel
    @State private var editing: DeadlineDraft?
    @State private var rescheduling: DeadlineRow?
    @State private var editingTrial: TrialEditorDraft?
    @State private var confirmingCancel: TrialSnapshot?
    @Environment(\.openURL) private var openURL

    var body: some View {
        List {
            if feeds.needsAttention {
                Section {
                    Label("A college feed needs attention. Open Settings to fix it.", systemImage: "exclamationmark.triangle")
                        .accessibilityIdentifier("deadlines.feedAttention")
                }
            }
            if planner.deadlines.isEmpty && planner.trialDeadlines.isEmpty {
                ContentUnavailableView {
                    Label("No deadlines", systemImage: "flag")
                } description: {
                    Text("Add a deadline and Eagar reminds you before it is due.")
                } actions: {
                    Button("Add deadline") { editing = planner.newDeadlineDraft() }
                }
            }
            rows(planner.overdueDeadlines, header: "Overdue")
            rows(planner.upcomingDeadlines, header: "Upcoming")
            rows(Array(planner.completedDeadlines.prefix(20)), header: "Done")
        }
        .navigationTitle(Text("Deadlines"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editing = planner.newDeadlineDraft()
                } label: {
                    Label("Add deadline", systemImage: "plus")
                }
                .accessibilityIdentifier("deadlines.add")
            }
        }
        .sheet(item: $editing) { DeadlineEditor(planner: planner, draft: $0) }
        .sheet(item: $editingTrial) { TrialEditor(money: money, draft: $0) }
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
        .sheet(item: $rescheduling) { row in
            RescheduleSheet(initial: row.snapshot.dueAt) { date in
                Task { await planner.reschedule(row.id, to: date) }
            }
        }
    }

    @ViewBuilder
    private func rows(_ rows: [DeadlineRow], header: LocalizedStringKey) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows) { row in
                    if row.snapshot.origin == .trial, let trial = money.trial(row.id) {
                        TrialDeadlineRowView(
                            row: row,
                            onEdit: { editingTrial = money.editDraft(trial.id) },
                            onCancel: {
                                openURL(money.cancelTarget(trial.id))
                                confirmingCancel = trial
                            },
                            onConfirmCancelled: { Task { await money.confirmCancelled(trial.id) } }
                        )
                    } else {
                        DeadlineRowView(
                            planner: planner, row: row,
                            loan: row.snapshot.origin == .booking ? feeds.loanInfo(forDeadline: row.id) : nil,
                            onEdit: { editing = DeadlineDraft(row) },
                            onReschedule: { rescheduling = row },
                            onAcceptReturn: { bookingID in Task { await feeds.acceptProposedReturn(bookingID: bookingID) } }
                        )
                    }
                }
            } header: {
                Text(header)
            }
        }
    }
}

/// A trial's cancel-by day among the deadlines (FR-DL-01). Its reminders are the trial's
/// own, so it has no reminder or snooze actions; Cancel and "I've cancelled" act on the trial.
private struct TrialDeadlineRowView: View {
    let row: DeadlineRow
    let onEdit: () -> Void
    let onCancel: () -> Void
    let onConfirmCancelled: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.snapshot.title)
                    Text("Due \(row.snapshot.dueAt, format: .dateTime.weekday(.wide).day().month())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label("Subscription", systemImage: "creditcard")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Edit subscription"))
            Menu {
                Button("Open the cancel page", action: onCancel)
                Button("I've cancelled it", action: onConfirmCancelled)
                Button("Edit subscription", action: onEdit)
            } label: {
                Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("More actions for \(row.snapshot.title)"))
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deadline.trialRow")
    }
}

/// A deadline with its actions. Swipe actions have button equivalents in the row's menu.
/// Loan returns add their location, links and a clash proposal under the row.
private struct DeadlineRowView: View {
    let planner: PlannerModel
    let row: DeadlineRow
    let loan: LoanRowInfo?
    let onEdit: () -> Void
    let onReschedule: () -> Void
    let onAcceptReturn: (String) -> Void
    @Environment(\.openURL) private var openURL

    private var snapshot: DeadlineSnapshot { row.snapshot }
    private var isOpen: Bool { snapshot.status == .open }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            mainRow
            if isOpen, let loan, let clash = loan.clash {
                LoanClashProposalView(clash: clash, accepted: loan.proposalAccepted) { onAcceptReturn(loan.bookingID) }
            }
        }
        .swipeActions(edge: .leading) {
            if isOpen {
                Button("Done") { Task { await planner.markDone(row.id) } }
            }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { Task { await planner.delete(row.id) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("deadline.row")
    }

    private var mainRow: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(snapshot.title)
                            .strikethrough(!isOpen)
                        if snapshot.dataClass == .college { BoundaryBadge() }
                    }
                    Group {
                        if snapshot.isAllDay {
                            Text("Due \(snapshot.dueAt, format: .dateTime.weekday(.wide).day().month())")
                        } else {
                            Text("Due \(snapshot.dueAt, format: .dateTime.weekday(.wide).day().month().hour().minute())")
                        }
                        if let snoozed = snapshot.snoozedUntil, snoozed > Date(), isOpen {
                            Text("Snoozed until \(snoozed, format: .dateTime.weekday().hour().minute())")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    DeadlineOriginCaption(origin: snapshot.origin, location: loan?.location)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Edit deadline"))

            if isOpen {
                Button {
                    Task { await planner.markDone(row.id) }
                } label: {
                    Image(systemName: "checkmark.circle").frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Mark \(snapshot.title) done"))
            }
            Menu {
                if isOpen {
                    Button("Snooze for 1 hour") { Task { await planner.snooze(row.id, until: planner.snoozeInAnHour) } }
                    Button("Snooze until tomorrow at 09:00") { Task { await planner.snooze(row.id, until: planner.snoozeTomorrowMorning) } }
                    Button("Reschedule", action: onReschedule)
                }
                if let page = loan?.pageURL {
                    Button("Open in cdbooking") { openURL(page) }
                }
                if isOpen, let extend = loan?.extendURL {
                    Button("Request an extension") { openURL(extend) }
                }
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive) { Task { await planner.delete(row.id) } }
            } label: {
                Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("More actions for \(snapshot.title)"))
        }
    }
}

/// Where a feed deadline came from, as a symbol and text.
private struct DeadlineOriginCaption: View {
    let origin: DeadlineOrigin
    let location: String?

    var body: some View {
        switch origin {
        case .booking:
            Group {
                if let location, !location.isEmpty {
                    Label("Loan · return to \(location)", systemImage: "camera")
                } else {
                    Label("Loan", systemImage: "camera")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        case .canvas:
            Label("Canvas", systemImage: "graduationcap")
                .font(.caption)
                .foregroundStyle(.secondary)
        default:
            EmptyView()
        }
    }
}

/// FR-BOOK-04: the due time falls in busy time. Proposes the latest free return time before it
/// (accepting adds a local college reminder; nothing is sent), or the extension page.
private struct LoanClashProposalView: View {
    let clash: ReturnClash
    let accepted: Bool
    let onAccept: () -> Void
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("You're busy when this is due.", systemImage: "exclamationmark.triangle")
                .font(.subheadline)
            if let slot = clash.proposedSlot {
                if accepted {
                    Label("Return reminder set for \(slot.start, format: .dateTime.weekday().hour().minute())", systemImage: "checkmark.circle")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Button(action: onAccept) {
                        Label("Remind me to return it at \(slot.start, format: .dateTime.weekday().hour().minute())", systemImage: "bell")
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("loan.acceptReturn")
                }
            } else if let extend = clash.extendURL {
                Button {
                    openURL(extend)
                } label: {
                    Label("No free time before then. Request an extension", systemImage: "arrow.up.forward.square")
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            } else {
                Text("No free time before then. Ask the loans desk for an extension.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("loan.clash")
    }
}

/// Add or edit a deadline (FR-DL-01, 02, 03).
struct DeadlineEditor: View {
    let planner: PlannerModel
    @State private var draft: DeadlineDraft
    @State private var confirmingDelete = false
    @State private var confirmingICloudOverride = false
    @Environment(\.dismiss) private var dismiss

    init(planner: PlannerModel, draft: DeadlineDraft) {
        self.planner = planner
        _draft = State(initialValue: draft)
    }

    private var isNew: Bool { draft.id == nil }
    private var eligibleLists: [CalendarInfo] { planner.eligibleReminderLists(for: draft) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $draft.title)
                        // Apple Intelligence Writing Tools could send a college title to Private
                        // Cloud Compute (BD-04): off for college deadlines.
                        .writingToolsBehavior(draft.dataClass == .college ? .disabled : .automatic)
                        .accessibilityIdentifier("deadline.title")
                    Toggle("All day", isOn: $draft.isAllDay)
                    DatePicker("Due", selection: $draft.dueAt, displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                }
                Section {
                    Picker("Data class", selection: $draft.dataClass) {
                        Text("Personal").tag(DataClass.personal)
                        Text("College").tag(DataClass.college)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Data class")
                } footer: {
                    if draft.dataClass == .college {
                        Text("College deadlines stay on your devices. Their notifications say \"College deadline\" without the title.")
                    } else {
                        Text("Notifications for personal deadlines show the title.")
                    }
                }
                Section {
                    ForEach(BriefLabels.offsetChoices, id: \.self) { minutes in
                        Toggle(isOn: Binding(
                            get: { draft.offsetsMinutes.contains(minutes) },
                            set: { on in
                                if on { draft.offsetsMinutes.insert(minutes) } else { draft.offsetsMinutes.remove(minutes) }
                            }
                        )) {
                            Text(BriefLabels.offset(minutes))
                        }
                    }
                } header: {
                    Text("Remind me")
                }
                if !planner.reminderLists.isEmpty {
                    Section {
                        Picker("Mirror to Reminders", selection: $draft.mirrorListID) {
                            Text("Don't mirror").tag(String?.none)
                            ForEach(eligibleLists) { list in
                                Text(verbatim: list.title).tag(Optional(list.id))
                            }
                        }
                        if draft.dataClass == .college {
                            Toggle("Allow iCloud Reminders for this deadline", isOn: Binding(
                                get: { draft.mirrorOverride },
                                set: { allow in
                                    // Turning it on copies a college title into iCloud: confirm first (FR-DL-03).
                                    if allow { confirmingICloudOverride = true } else { draft.mirrorOverride = false }
                                }
                            ))
                            .confirmationDialog(
                                "Copy this college deadline to iCloud Reminders?",
                                isPresented: $confirmingICloudOverride,
                                titleVisibility: .visible
                            ) {
                                Button("Allow for this deadline") { draft.mirrorOverride = true }
                                Button("Cancel", role: .cancel) {}
                            } message: {
                                Text("Its title will be stored in iCloud. Other college deadlines are not affected.")
                            }
                        }
                    } header: {
                        Text("Reminders")
                    } footer: {
                        if draft.dataClass == .college {
                            Text("College deadlines mirror only to lists tagged college or kept on this device, unless you allow iCloud for this one.")
                        }
                    }
                }
                if !isNew {
                    Section {
                        Button("Delete deadline", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(isNew ? Text("New deadline") : Text("Edit deadline"))
            .onChange(of: eligibleLists) {
                if let id = draft.mirrorListID, !eligibleLists.contains(where: { $0.id == id }) { draft.mirrorListID = nil }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await planner.save(draft) { dismiss() }
                        }
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .accessibilityIdentifier("deadline.save")
                }
            }
            .confirmationDialog("Delete this deadline?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    if let id = draft.id {
                        Task {
                            await planner.delete(id)
                            dismiss()
                        }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 520)
        #endif
    }
}
