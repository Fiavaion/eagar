import EagarCalendar
import EagarCore
import SwiftUI

/// A new event typed by Mark (FR-CAL-04). It is derived from nothing, so it may go to any
/// modifiable calendar; ``CalendarWriter`` still enforces the boundary, and its refusals are
/// shown here.
struct EventEditor: View {
    let planner: PlannerModel
    @State private var title = ""
    @State private var start: Date
    @State private var end: Date
    @State private var isAllDay = false
    @State private var calendarID: String?
    @State private var error: CalendarError?
    @State private var saving = false
    @Environment(\.dismiss) private var dismiss

    init(planner: PlannerModel, start: Date) {
        self.planner = planner
        _start = State(initialValue: start)
        _end = State(initialValue: start.addingTimeInterval(3600))
        _calendarID = State(initialValue: planner.modifiableEventCalendars.first?.id)
    }

    private var calendars: [CalendarInfo] { planner.modifiableEventCalendars }
    private var selected: CalendarInfo? { calendars.first { $0.id == calendarID } }
    /// With no calendar chosen yet, treat the text as college (fail closed for Writing Tools).
    private var isCollege: Bool { selected.map { planner.tag(for: $0).dataClass == .college } ?? true }
    private var trimmedTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSave: Bool { !trimmedTitle.isEmpty && selected != nil && end >= start && !saving }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                        // Writing Tools could send a college title to Private Cloud Compute (BD-04).
                        .writingToolsBehavior(isCollege ? .disabled : .automatic)
                        .accessibilityIdentifier("event.title")
                    Toggle("All day", isOn: $isAllDay)
                        .frame(minHeight: 44)
                    DatePicker("Starts", selection: $start, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("Ends", selection: $end, in: start..., displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
                }
                Section {
                    if calendars.isEmpty {
                        Text("No calendar can take new events. Allow calendar access, or add a calendar in the Calendar app.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Calendar", selection: $calendarID) {
                            ForEach(calendars) { calendar in
                                HStack {
                                    Text(verbatim: calendar.title)
                                    Spacer(minLength: 8)
                                    ProcessingModeLabel(dataClass: planner.tag(for: calendar).dataClass, compact: true)
                                }
                                .frame(minHeight: 44)
                                .tag(Optional(calendar.id))
                            }
                        }
                        .pickerStyle(.inline)
                        .accessibilityIdentifier("event.calendar")
                    }
                } header: {
                    Text("Calendar")
                } footer: {
                    if let selected {
                        ProcessingModeLabel(dataClass: planner.tag(for: selected).dataClass)
                    }
                }
                if let error {
                    Section {
                        Label {
                            Text(Self.message(for: error))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                        }
                        .accessibilityIdentifier("event.error")
                    }
                }
            }
            .navigationTitle(Text("New event"))
            .onChange(of: start) { old, new in
                // Keep the length when the start moves.
                end = new.addingTimeInterval(max(0, end.timeIntervalSince(old)))
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(!canSave)
                        .accessibilityIdentifier("event.save")
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 420)
        #endif
    }

    private func save() {
        guard let calendar = selected else { return }
        let draft = EventDraft(title: trimmedTitle, start: start, end: end, isAllDay: isAllDay)
        saving = true
        Task {
            let failure = await planner.saveEvent(draft, to: calendar)
            saving = false
            if let failure {
                error = failure
            } else {
                dismiss()
            }
        }
    }

    static func message(for error: CalendarError) -> LocalizedStringResource {
        switch error {
        case .crossBoundaryWrite: "College content can only be added to a calendar tagged college."
        case .readOnlyCalendar: "This calendar cannot be changed. Choose another calendar."
        case .accessDenied: "Eagar does not have calendar access. Allow it in the Settings app."
        case .calendarNotFound: "That calendar is no longer available. Choose another calendar."
        case .saveFailed, .fetchFailed: "Eagar could not save the event."
        }
    }
}
