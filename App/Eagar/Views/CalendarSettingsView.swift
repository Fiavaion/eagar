import EagarCalendar
import EagarCore
import SwiftUI

/// Explains why Eagar needs full calendar access before asking for it (FR-CAL-01).
struct CalendarAccessExplanation: View {
    let planner: PlannerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Calendar access", systemImage: "calendar")
                .font(.headline)
            Text("Eagar reads your calendars to build your brief and find free time, and reads your reminder lists so you can mirror deadlines to them. It adds events and reminders only when you ask.")
            Text("Apple offers only full access, so Eagar asks for it. Events from calendars you tag as college stay on your devices.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            switch planner.access {
            case .denied, .restricted, .writeOnly:
                Text("Calendar access is turned off. To turn it on, open the Settings app, choose Apps, then Eagar, and allow full access to Calendars and Reminders.")
                    .font(.footnote)
            case .notDetermined, .fullAccess:
                Button("Allow calendar access") {
                    Task { await planner.requestCalendarAccess() }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .accessibilityIdentifier("calendar.allow")
            }
        }
        .padding(.vertical, 4)
    }
}

/// One calendar or reminder list with its college/personal tag and brief toggle (FR-CAL-02).
struct CalendarTagRow: View {
    let planner: PlannerModel
    let calendar: CalendarInfo
    let showsBriefToggle: Bool

    var body: some View {
        let tag = planner.tag(for: calendar)
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: calendar.title)
                    if !calendar.accountTitle.isEmpty {
                        Text(verbatim: calendar.accountTitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                if !tag.confirmed {
                    Text("Proposed")
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .overlay(Capsule().strokeBorder(.secondary))
                        .accessibilityLabel(Text("Proposed tag, not yet confirmed"))
                }
                if tag.dataClass == .college { BoundaryBadge() }
            }
            Picker(selection: Binding(
                get: { tag.dataClass },
                set: { new in Task { await planner.setTag(calendar, dataClass: new, includeInBrief: tag.includeInBrief) } }
            )) {
                Text("Personal").tag(DataClass.personal)
                Text("College").tag(DataClass.college)
            } label: {
                Text("Tag for \(calendar.title)")
            }
            .pickerStyle(.segmented)
            .frame(minHeight: 44)
            if showsBriefToggle {
                Toggle("Include in brief", isOn: Binding(
                    get: { tag.includeInBrief },
                    set: { new in Task { await planner.setTag(calendar, dataClass: tag.dataClass, includeInBrief: new) } }
                ))
                .frame(minHeight: 44)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
    }
}

/// Calendar access, tags and the missing-NCAD-calendar diagnosis (FR-CAL-01, 02, 06).
struct CalendarSettingsSections: View {
    let planner: PlannerModel

    var body: some View {
        if planner.access != .fullAccess {
            Section {
                CalendarAccessExplanation(planner: planner)
            }
        } else {
            Section {
                if planner.eventCalendars.isEmpty {
                    Text("No calendars found.")
                        .foregroundStyle(.secondary)
                }
                ForEach(planner.eventCalendars) { CalendarTagRow(planner: planner, calendar: $0, showsBriefToggle: true) }
            } header: {
                Text("Calendars")
            } footer: {
                Text("Calendars on an ncad.ie account are proposed as college. College events stay on your devices: they are never sent to Claude, synced or shown in notifications.")
            }
            if !planner.reminderLists.isEmpty {
                Section {
                    ForEach(planner.reminderLists) { CalendarTagRow(planner: planner, calendar: $0, showsBriefToggle: false) }
                } header: {
                    Text("Reminder lists")
                } footer: {
                    Text("College deadlines can be mirrored only to lists tagged college or kept on this device.")
                }
            }
            if planner.isCollegeCalendarMissing {
                Section {
                    MissingCollegeCalendarSteps()
                } header: {
                    Text("NCAD calendar not found")
                }
            }
        }
    }
}

/// FR-CAL-06: how to add the NCAD Google account to Apple Calendar.
struct MissingCollegeCalendarSteps: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Eagar did not find a calendar from an ncad.ie account. To add it:")
            Text("1. Open the Settings app.")
            Text("2. Choose Apps, then Calendar, then Calendar Accounts.")
            Text("3. Choose Add Account, then Google, and sign in with your NCAD address.")
            Text("4. Turn on Calendars for that account, then come back to Eagar.")
            Text("NCAD IT may block Apple's Calendar app from your college account. If sign-in is refused, ask IT whether Apple Calendar is allowed.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("calendar.missingCollege")
    }
}
