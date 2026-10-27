import EagarCore
import EagarPeople
import SwiftUI

/// Keep in touch (FR-PEOPLE-01..06): this week's suggestions, people and their cadences.
struct PeopleView: View {
    let people: PeopleModel
    @State private var editing: PersonEditorDraft?
    @State private var adding = false

    var body: some View {
        List {
            Section {
                if people.nudges.isEmpty {
                    Text(people.people.isEmpty ? "Add people and Eagar suggests catch-ups in your free time." : "No catch-ups to suggest this week.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(people.nudges) { nudge in
                        NudgeRow(people: people, nudge: nudge)
                    }
                }
                Stepper(value: Binding(get: { people.weeklyBudget }, set: { people.weeklyBudget = $0 }), in: 0...14) {
                    Text("Up to \(people.weeklyBudget) catch-ups a week")
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("people.budget")
            } header: {
                Text("This week")
            } footer: {
                Text("Catch-ups left this week: \(people.budgetLeft). Suggestions use real gaps in your calendar.")
            }
            if people.people.isEmpty {
                ContentUnavailableView {
                    Label("No people yet", systemImage: "person.2")
                } description: {
                    Text("Choose the people you want to keep in touch with. Eagar never reads contact notes.")
                } actions: {
                    Button("Add someone") { adding = true }
                }
            } else {
                Section {
                    ForEach(people.sortedPeople) { record in
                        PersonRow(people: people, record: record) { editing = PersonEditorDraft(record) }
                    }
                } header: {
                    Text("People")
                }
            }
        }
        .navigationTitle(Text("People"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    adding = true
                } label: {
                    Label("Add someone", systemImage: "plus")
                }
                .accessibilityIdentifier("people.add")
            }
        }
        .refreshable { await people.refresh() }
        .sheet(isPresented: $adding) { AddPersonSheet(people: people) }
        .sheet(item: $editing) { PersonEditor(people: people, draft: $0) }
    }
}

/// One suggested catch-up with its actions (FR-PEOPLE-05). A college-class nudge (its slot
/// follows a college event) carries the boundary badge.
struct NudgeRow: View {
    let people: PeopleModel
    let nudge: Nudge

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(NudgePhrasing.text(for: nudge, calendar: .current))
                    .font(.body.weight(.medium))
                Spacer(minLength: 8)
                if nudge.dataClass == .college { BoundaryBadge() }
            }
            Text(nudge.slot.start..<nudge.slot.end, format: .interval.weekday().hour().minute())
                .font(.subheadline)
                .foregroundStyle(.secondary)
            NudgeActionButtons(name: nudge.displayName) { action in
                Task { await people.perform(action, on: nudge) }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("nudge.row")
    }
}

/// Plan, log contact, snooze and change cadence, as buttons and menus with 44 pt targets.
struct NudgeActionButtons: View {
    let name: String
    let perform: (NudgeAction) -> Void

    static let snoozeChoices = [7, 14]
    static let cadenceChoices = [7, 14, 30, 60, 90]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { buttons }
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 12) { primary }
                HStack(spacing: 12) { secondary }
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        primary
        secondary
    }

    @ViewBuilder private var primary: some View {
        Button {
            perform(.plan)
        } label: {
            Label("Plan", systemImage: "calendar.badge.plus").frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityLabel(Text("Plan a catch-up with \(name)"))
        Button {
            perform(.logContact(at: .now))
        } label: {
            Label("We talked", systemImage: "checkmark.bubble").frame(minHeight: 44)
        }
        .buttonStyle(.borderless)
        .fixedSize()
        .accessibilityLabel(Text("Log that you talked to \(name)"))
    }

    @ViewBuilder private var secondary: some View {
        Menu {
            ForEach(Self.snoozeChoices, id: \.self) { days in
                Button { perform(.snooze(days: days)) } label: { Text(PersonLabels.snooze(days)) }
            }
        } label: {
            Label("Snooze", systemImage: "moon.zzz").frame(minHeight: 44)
        }
        .fixedSize()
        .accessibilityLabel(Text("Snooze suggestions for \(name)"))
        Menu {
            ForEach(Self.cadenceChoices, id: \.self) { days in
                Button { perform(.changeCadence(days: days)) } label: { Text(PersonLabels.cadence(days)) }
            }
        } label: {
            Label("Cadence", systemImage: "arrow.triangle.2.circlepath").frame(minHeight: 44)
        }
        .fixedSize()
        .accessibilityLabel(Text("Change how often to see \(name)"))
    }
}

enum PersonLabels {
    static func cadence(_ days: Int) -> LocalizedStringResource {
        switch days {
        case 7: "Every week"
        case 14: "Every 2 weeks"
        case 30: "Every month"
        case 60: "Every 2 months"
        case 90: "Every 3 months"
        case 180: "Every 6 months"
        default: "Every \(days) days"
        }
    }

    static func snooze(_ days: Int) -> LocalizedStringResource {
        days == 7 ? "For a week" : "For \(days / 7) weeks"
    }

    static func weekday(_ number: Int) -> String {
        Calendar.current.weekdaySymbols[(number - 1) % 7]
    }
}

/// A person with "We talked" and a menu; tapping edits.
private struct PersonRow: View {
    let people: PeopleModel
    let record: PersonRecord
    let onEdit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(record.snapshot.displayName).font(.body.weight(.medium))
                        if people.isDue(record) {
                            Text("Due")
                                .font(.caption)
                                .padding(.horizontal, 6)
                                .overlay(Capsule().strokeBorder(.secondary))
                        }
                    }
                    Group {
                        if let last = people.lastContact(record) {
                            Text("Last in touch \(last, format: .relative(presentation: .named))")
                        } else {
                            Text("No contact yet")
                        }
                        Text(PersonLabels.cadence(record.snapshot.cadenceDays))
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(Text("Edit person"))
            if people.lastContactIsCollege(record) { BoundaryBadge() }
            Button {
                Task { await people.logContact(record.id) }
            } label: {
                Image(systemName: "checkmark.bubble").frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Log that you talked to \(record.snapshot.displayName)"))
            Menu {
                Button("We talked today") { Task { await people.logContact(record.id) } }
                Button("Edit", action: onEdit)
                Button("Delete", role: .destructive) { Task { await people.delete(record.id) } }
            } label: {
                Image(systemName: "ellipsis.circle").frame(minWidth: 44, minHeight: 44)
            }
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel(Text("More actions for \(record.snapshot.displayName)"))
        }
        .swipeActions(edge: .leading) {
            Button("We talked") { Task { await people.logContact(record.id) } }
        }
        .swipeActions(edge: .trailing) {
            Button("Delete", role: .destructive) { Task { await people.delete(record.id) } }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("person.row")
    }
}

/// Add people from Contacts, or by name.
private struct AddPersonSheet: View {
    let people: PeopleModel
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                ContactPickerSection(
                    onPicked: { contacts in
                        Task {
                            await people.add(contacts)
                            if !contacts.isEmpty { dismiss() }
                        }
                    },
                    onFailure: { people.failure = .contacts }
                )
                Section {
                    TextField("Name", text: $name)
                        .accessibilityIdentifier("person.name")
                    Button("Add") {
                        Task {
                            if await people.add(name: name) != nil { dismiss() }
                        }
                    }
                    .frame(minHeight: 44)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("By name")
                }
            }
            .navigationTitle(Text("Add someone"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 360)
        #endif
    }
}

/// Cadence, weekdays, notes and the work-signal opt-in (FR-PEOPLE-02, 03).
struct PersonEditor: View {
    let people: PeopleModel
    @State private var draft: PersonEditorDraft
    @State private var confirmingDelete = false
    @Environment(\.dismiss) private var dismiss

    init(people: PeopleModel, draft: PersonEditorDraft) {
        self.people = people
        _draft = State(initialValue: draft)
    }

    static let cadenceChoices = [7, 14, 30, 60, 90, 180]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $draft.displayName)
                    if let birthday = draft.birthday {
                        LabeledContent("Birthday") { Text(Self.birthdayText(birthday)) }
                    }
                    Button("We talked today") {
                        Task {
                            await people.logContact(draft.id)
                            dismiss()
                        }
                    }
                    .frame(minHeight: 44)
                }
                Section {
                    Picker("How often", selection: $draft.cadenceDays) {
                        ForEach(Self.cadenceChoices + (Self.cadenceChoices.contains(draft.cadenceDays) ? [] : [draft.cadenceDays]), id: \.self) {
                            Text(PersonLabels.cadence($0)).tag($0)
                        }
                    }
                    ForEach(1...7, id: \.self) { weekday in
                        Toggle(PersonLabels.weekday(weekday), isOn: Binding(
                            get: { draft.preferredWeekdays.contains(weekday) },
                            set: { on in
                                if on { draft.preferredWeekdays.insert(weekday) } else { draft.preferredWeekdays.remove(weekday) }
                            }
                        ))
                    }
                } header: {
                    Text("Keep in touch")
                } footer: {
                    Text("With no days chosen, any day works.")
                }
                Section {
                    TextEditor(text: $draft.notes)
                        .frame(minHeight: 100)
                        .accessibilityLabel(Text("Relationship notes"))
                } header: {
                    Text("Notes")
                } footer: {
                    Label("Your notes sync between your devices end-to-end encrypted in iCloud. Eagar never reads contact notes.", systemImage: "lock.icloud")
                }
                Section {
                    Toggle("Count college calendar events", isOn: $draft.workSignalsOptIn)
                } header: {
                    Text("College signals")
                } footer: {
                    Text("When on, meetings with this person in college calendars count as contact. That information stays on this device and is never synced.")
                }
                let history = people.logs(for: draft.id)
                if !history.isEmpty {
                    Section {
                        ForEach(history.prefix(10)) { entry in
                            Text(entry.occurredAt, format: .dateTime.weekday(.wide).day().month().year())
                        }
                    } header: {
                        Text("Logged contact")
                    }
                }
                Section {
                    Button("Remove from keep in touch", role: .destructive) { confirmingDelete = true }
                }
            }
            .navigationTitle(Text("Edit person"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await people.save(draft) { dismiss() } }
                    }
                    .disabled(draft.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog("Remove this person?", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    Task {
                        await people.delete(draft.id)
                        dismiss()
                    }
                }
            } message: {
                Text("Their logged contact is removed too. The contact in Contacts is not changed.")
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 560)
        #endif
    }

    static func birthdayText(_ birthday: Birthday) -> String {
        var components = DateComponents(year: birthday.year ?? 2000, month: birthday.month, day: birthday.day)
        components.calendar = Calendar.current
        guard let date = components.date else { return "" }
        return birthday.year == nil ? date.formatted(.dateTime.day().month(.wide)) : date.formatted(.dateTime.day().month(.wide).year())
    }
}
