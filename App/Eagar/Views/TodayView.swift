import EagarBrief
import EagarCalendar
import EagarCore
import SwiftUI

/// The Brief for the current slot and the day timeline (FR-BRIEF-01..08, FR-CAL-05).
struct TodayView: View {
    let model: AppModel
    private var planner: PlannerModel { model.planner }
    @State private var editing: DeadlineDraft?
    @State private var confirmingCancel: BriefItem?
    @Environment(\.openURL) private var openURL
    @State private var rescheduling: BriefItem?
    @State private var viewingEvent: ClassifiedEvent?
    @State private var addingEvent = false

    var body: some View {
        List {
            if planner.access != .fullAccess {
                Section {
                    CalendarAccessExplanation(planner: planner)
                }
            }
            if let brief = planner.brief {
                BriefSections(
                    planner: planner, brief: brief,
                    onOpen: open, onReschedule: { rescheduling = $0 }, onExtra: perform
                )
            }
            Section {
                let items = planner.timeline
                if items.isEmpty {
                    Text("Nothing on your timeline today.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(items) { TimelineRow(item: $0) }
                }
            } header: {
                Text("Timeline")
            }
        }
        .navigationTitle(Text("Today"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button {
                        editing = planner.newDeadlineDraft()
                    } label: {
                        Label("New deadline", systemImage: "flag")
                    }
                    .accessibilityIdentifier("today.addDeadline")
                    Button {
                        addingEvent = true
                    } label: {
                        Label("New event", systemImage: "calendar.badge.plus")
                    }
                    .accessibilityIdentifier("today.addEvent")
                } label: {
                    Label("Add", systemImage: "plus")
                }
                .accessibilityIdentifier("today.add")
            }
        }
        .refreshable { await model.refresh() }
        // Re-run whenever the shown brief changes, so the open is logged once the brief exists
        // (FR-BRIEF-08, SM2), not only on first appearance.
        .task(id: planner.brief?.id) { await planner.briefOpened() }
        .sheet(isPresented: $addingEvent) {
            EventEditor(planner: planner, start: planner.newEventStart)
        }
        .sheet(item: $editing) { draft in
            DeadlineEditor(planner: planner, draft: draft)
        }
        .sheet(item: $rescheduling) { item in
            RescheduleSheet(initial: item.start ?? planner.snoozeTomorrowMorning) { date in
                Task { await planner.reschedule(item, to: date) }
            }
        }
        .sheet(item: $viewingEvent) { event in
            EventDetailView(event: event, calendarTitle: planner.eventCalendars.first { $0.id == event.event.calendarID }?.title)
        }
        .confirmationDialog(
            Text("Did you cancel \(confirmingCancel?.title ?? "")?"),
            isPresented: Binding(get: { confirmingCancel != nil }, set: { if !$0 { confirmingCancel = nil } }),
            titleVisibility: .visible,
            presenting: confirmingCancel
        ) { item in
            Button("Yes, I cancelled it") { perform(.confirmCancelled, on: item) }
            Button("Not yet", role: .cancel) {}
        } message: { _ in
            Text("Eagar records a cancellation only when you confirm it.")
        }
    }

    private func open(_ item: BriefItem) {
        Task { await planner.perform(.open, on: item) }
        if item.kind == .subscriptionSummary {
            NotificationCenter.default.post(name: .eagarShowTab, object: RootTab.subscriptions.rawValue)
        } else if let row = planner.row(for: item) {
            editing = DeadlineDraft(row)
        } else if let event = planner.event(for: item) {
            viewingEvent = event
        }
    }

    /// Trial actions (FR-TRIAL-05). Cancel opens the cancel page and then asks Mark to
    /// confirm; only his confirmation records the cancellation.
    private func perform(_ action: BriefAction, on item: BriefItem) {
        switch action {
        case .cancelSubscription:
            guard let id = Self.trialID(item) else { return }
            openURL(model.money.cancelTarget(id))
            confirmingCancel = item
            Task { await planner.record(.cancelSubscription, on: item) }
        case .confirmCancelled:
            guard let id = Self.trialID(item) else { return }
            Task {
                await planner.record(.confirmCancelled, on: item)
                await model.money.confirmCancelled(id)
            }
        default:
            break
        }
    }

    static func trialID(_ item: BriefItem) -> UUID? {
        guard item.kind == .trial else { return nil }
        return UUID(uuidString: String(item.id.dropFirst("trial.".count)))
    }
}

/// The brief's sections with their optional phrasing and items.
private struct BriefSections: View {
    let planner: PlannerModel
    let brief: Brief
    let onOpen: (BriefItem) -> Void
    let onReschedule: (BriefItem) -> Void
    let onExtra: (BriefAction, BriefItem) -> Void

    var body: some View {
        if brief.isEmpty {
            Section {
                Text("Nothing needs you right now.")
                    .accessibilityIdentifier("brief.empty")
            } header: {
                Text(BriefLabels.slot(brief.slot.kind))
            }
        }
        ForEach(Array(brief.sections.enumerated()), id: \.element.id) { index, section in
            Section {
                if let phrased = planner.phrasing[section.kind] {
                    PhrasingView(section: phrased)
                }
                ForEach(section.items) { item in
                    BriefItemRow(planner: planner, item: item, onOpen: onOpen, onReschedule: onReschedule, onExtra: onExtra)
                }
                if section.hiddenCount > 0 {
                    Text("More not shown: \(section.hiddenCount)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    if index == 0 {
                        Text(BriefLabels.slot(brief.slot.kind))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Text(BriefLabels.section(section.kind))
                        .accessibilityAddTraits(.isHeader)
                }
            }
        }
    }
}

/// Optional AI phrasing under a section header, with where it was processed (FR-AI-12).
private struct PhrasingView: View {
    let section: PhrasedSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Array(section.parts.enumerated()), id: \.offset) { _, part in
                Text(part.text)
                    .italic()
                HStack(spacing: 8) {
                    Text("AI summary")
                    if let tier = part.tier { TierBadge(tier: tier) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("brief.phrasing")
    }
}

/// One brief item with its actions (FR-BRIEF-03) and thumbs (FR-BRIEF-07).
private struct BriefItemRow: View {
    let planner: PlannerModel
    let item: BriefItem
    let onOpen: (BriefItem) -> Void
    let onReschedule: (BriefItem) -> Void
    let onExtra: (BriefAction, BriefItem) -> Void

    private var state: BriefAction? { planner.itemStates[item.id] }
    private var isSettled: Bool { state.map { $0.dealsWithItem && $0 != .snooze } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.title)
                    .font(.body.weight(.medium))
                    .strikethrough(isSettled)
                Spacer(minLength: 8)
                if item.dataClass == .college { BoundaryBadge() }
            }
            if let detail = item.detail {
                Text(detail)
                    .font(.subheadline)
            }
            ItemTime(item: item)
            if let state {
                Label {
                    Text(BriefLabels.state(state))
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) { actions; Spacer(); thumbs }
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) { actions }
                    HStack(spacing: 8) { thumbs }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("brief.item")
    }

    @ViewBuilder private var actions: some View {
        ForEach(item.actions, id: \.self) { action in
            switch action {
            case .open:
                ActionButton(title: "Open", systemImage: "arrow.up.forward.square", label: "Open \(item.title)") { onOpen(item) }
            case .done:
                ActionButton(title: "Done", systemImage: "checkmark", label: "Mark \(item.title) done") {
                    Task { await planner.perform(.done, on: item) }
                }
            case .dismiss:
                ActionButton(title: "Dismiss", systemImage: "xmark", label: "Dismiss \(item.title)") {
                    Task { await planner.perform(.dismiss, on: item) }
                }
            case .reschedule:
                ActionButton(title: "Reschedule", systemImage: "calendar", label: "Reschedule \(item.title)") { onReschedule(item) }
            case .snooze:
                Menu {
                    Button("In 1 hour") { Task { await planner.snooze(item, until: planner.snoozeInAnHour) } }
                    Button("Tomorrow at 09:00") { Task { await planner.snooze(item, until: planner.snoozeTomorrowMorning) } }
                } label: {
                    Label("Snooze", systemImage: "moon.zzz")
                        .frame(minHeight: 44)
                }
                .fixedSize()
                .accessibilityLabel(Text("Snooze \(item.title)"))
            case .cancelSubscription:
                ActionButton(title: "Cancel…", systemImage: "creditcard", label: "Open the cancel page for \(item.title)") { onExtra(.cancelSubscription, item) }
            case .confirmCancelled:
                ActionButton(title: "Cancelled", systemImage: "checkmark", label: "I've cancelled \(item.title)") { onExtra(.confirmCancelled, item) }
            case .plan, .logContact, .changeCadence:
                EmptyView()
            }
        }
        .disabled(isSettled)
    }

    @ViewBuilder private var thumbs: some View {
        let rating = planner.ratings[item.id]
        Button {
            Task { await planner.rate(item, helpful: true) }
        } label: {
            Image(systemName: rating == true ? "hand.thumbsup.fill" : "hand.thumbsup")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Useful"))
        .accessibilityValue(rating == true ? Text("Selected") : Text(verbatim: ""))
        Button {
            Task { await planner.rate(item, helpful: false) }
        } label: {
            Image(systemName: rating == false ? "hand.thumbsdown.fill" : "hand.thumbsdown")
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Not useful"))
        .accessibilityValue(rating == false ? Text("Selected") : Text(verbatim: ""))
    }
}

/// A bordered action with a 44 pt target and a specific VoiceOver label.
private struct ActionButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityLabel(Text(label))
    }
}

/// The time line under a brief item.
private struct ItemTime: View {
    let item: BriefItem

    var body: some View {
        Group {
            if item.kind == .trial || item.kind == .subscriptionSummary {
                EmptyView()
            } else if item.kind == .nudge, let start = item.start, let end = item.end, end > start {
                Text(start..<end, format: .interval.weekday().hour().minute())
            } else if item.kind == .deadline, let start = item.start {
                if item.isAllDay {
                    Text("Due \(start, format: .dateTime.weekday(.wide).day().month())")
                } else {
                    Text("Due \(start, format: .dateTime.weekday(.wide).hour().minute())")
                }
            } else if item.isAllDay {
                Text("All day")
            } else if let start = item.start, let end = item.end, end > start {
                Text(start..<end, format: .interval.hour().minute())
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}

/// One timeline line: time, a marker (shape differs by kind), title and boundary badge.
private struct TimelineRow: View {
    let item: TimelineItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Group {
                if item.isAllDay {
                    Text("All day")
                } else {
                    Text(item.start, format: .dateTime.hour().minute())
                }
            }
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(minWidth: 64, alignment: .leading)
            Image(systemName: item.kind == .deadline ? "flag" : "circle.fill")
                .imageScale(.small)
                .foregroundStyle(item.dataClass == .college ? Color.orange : Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                if item.kind == .deadline {
                    Text("Deadline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if item.dataClass == .college { BoundaryBadge() }
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("timeline.item")
    }
}

/// Details of a brief event (the event's Open action).
private struct EventDetailView: View {
    let event: ClassifiedEvent
    let calendarTitle: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(event.event.title).font(.headline)
                    if event.event.isAllDay {
                        Text("All day")
                    } else {
                        Text(event.event.start..<event.event.end, format: .interval.weekday().hour().minute())
                    }
                    if let location = event.event.location, !location.isEmpty {
                        LabeledContent("Location") { Text(verbatim: location) }
                    }
                    if let calendarTitle {
                        LabeledContent("Calendar") { Text(verbatim: calendarTitle) }
                    }
                    LabeledContent("Data class") { Text(DataClassLabel.name(event.dataClass)) }
                    if event.dataClass == .college { BoundaryBadge() }
                }
            }
            .navigationTitle(Text("Event"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 300)
        #endif
    }
}

/// Picks a new due time for an overdue deadline (FR-DL-04).
struct RescheduleSheet: View {
    let initial: Date
    let onSave: (Date) -> Void
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(initial: Date, onSave: @escaping (Date) -> Void) {
        self.initial = initial
        self.onSave = onSave
        _date = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("New due time", selection: $date)
            }
            .navigationTitle(Text("Reschedule"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(date)
                        dismiss()
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 200)
        #endif
    }
}
