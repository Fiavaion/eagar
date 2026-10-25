import EagarBrief
import SwiftUI

/// Settings for M1: calendars and the brief (FR-CAL-02, FR-BRIEF-01, 04, 07).
struct SettingsView: View {
    let model: AppModel
    private var planner: PlannerModel { model.planner }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.killSwitchEngaged }, set: { on in Task { await model.setKillSwitch(on) } })) {
                    Label("Stop all AI", systemImage: "stop.circle")
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("settings.killSwitch")
            } header: {
                Text("Kill switch")
            } footer: {
                Text("Stops all drafting and AI at once. Also in Control Centre and Shortcuts.")
            }
            if model.syncAvailable {
                Section {
                    if model.syncPausedForAccountChange {
                        Text("Your iCloud account changed, so syncing is paused. Your data is still on this device.")
                        Button("Sync with this iCloud account") { Task { await model.confirmICloudAccount() } }
                            .frame(minHeight: 44)
                    } else {
                        Label("Personal deadlines sync through your iCloud account. College data never does.", systemImage: "icloud")
                    }
                } header: {
                    Text("iCloud")
                }
            }
            CalendarSettingsSections(planner: planner)
            BriefSettingsSections(planner: planner)
            Section {
                Button("Allow brief and deadline notifications") {
                    Task { await planner.requestNotificationAuthorisation() }
                }
                .frame(minHeight: 44)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Brief notifications show counts only. Personal deadline reminders show their title; college ones say \"College deadline\" without a title.")
            }
        }
        .navigationTitle(Text("Settings"))
        .accessibilityIdentifier("settings.form")
    }
}

/// Brief times, sections and phrasing.
private struct BriefSettingsSections: View {
    let planner: PlannerModel

    private var settings: Binding<BriefSettings> {
        Binding(get: { planner.settings }, set: { planner.settings = $0 })
    }

    var body: some View {
        Section {
            ForEach(planner.settings.slots.indices, id: \.self) { index in
                SlotRow(slot: settings.slots[index])
            }
        } header: {
            Text("Brief times")
        } footer: {
            Text("Each brief arrives at the first natural break after its time: the end of an event, a free gap of 15 minutes or opening Eagar. It is never more than 45 minutes late.")
        }

        Section {
            LabeledContent {
                Text("Always first")
            } label: {
                Text(BriefLabels.section(.overdue))
            }
            let order = planner.settings.orderedSteerableSections
            ForEach(Array(order.enumerated()), id: \.element) { index, kind in
                SectionRow(
                    kind: kind, settings: settings,
                    canMoveUp: index > 0, canMoveDown: index < order.count - 1
                )
            }
        } header: {
            Text("Sections")
        } footer: {
            Text("Overdue deadlines always come first. Thumbs up and down on brief items help Eagar learn what matters to you.")
        }

        Section {
            Picker("Phrasing", selection: settings.phrasingMode) {
                // "Claude for personal items" is hidden until consent screens exist (Parked,
                // FR-PRIV-07): without consent every attempt would only be blocked.
                ForEach(BriefPhrasingMode.allCases.filter { $0 != .claudeForPersonal }, id: \.self) { mode in
                    Text(BriefLabels.phrasing(mode)).tag(mode)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } header: {
            Text("AI phrasing")
        } footer: {
            switch planner.settings.phrasingMode {
            case .off:
                Text("The brief shows plain lists, with no AI.")
            case .localOnly:
                Text("A short summary is written on this device or your Mac. Nothing is sent anywhere.")
            case .claudeForPersonal:
                Text("Personal items may be summarised by Claude, using your Claude key, once you have given consent for it. College items are always summarised on your devices only. Every call appears in the privacy ledger.")
            }
        }
    }
}

private struct SlotRow: View {
    @Binding var slot: BriefSettings.SlotSetting

    private var time: Binding<Date> {
        Binding(
            get: { Calendar.current.date(bySettingHour: slot.hour, minute: slot.minute, second: 0, of: Date()) ?? Date() },
            set: { date in
                let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
                slot.hour = parts.hour ?? slot.hour
                slot.minute = parts.minute ?? slot.minute
            }
        )
    }

    var body: some View {
        Toggle(isOn: $slot.enabled) { Text(BriefLabels.slot(slot.kind)) }
            .frame(minHeight: 44)
        if slot.enabled {
            DatePicker(selection: time, displayedComponents: .hourAndMinute) {
                Text("Time")
            }
            .accessibilityLabel(Text("Time for \(Text(BriefLabels.slot(slot.kind)))"))
        }
    }
}

/// Show, size and move one section (buttons, not drag, so it works with VoiceOver and Switch Control).
private struct SectionRow: View {
    let kind: BriefSectionKind
    @Binding var settings: BriefSettings
    let canMoveUp: Bool
    let canMoveDown: Bool

    private var shown: Binding<Bool> {
        Binding(
            get: { !settings.preferences.hidden.contains(kind) },
            set: { show in
                if show { settings.preferences.hidden.remove(kind) } else { settings.preferences.hidden.insert(kind) }
            }
        )
    }

    private var limit: Binding<Int> {
        Binding(
            get: { settings.preferences.maxItems[kind] ?? 8 },
            set: { settings.preferences.maxItems[kind] = $0 }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(isOn: shown) { Text(BriefLabels.section(kind)) }
                Button {
                    settings.move(kind, by: -1)
                } label: {
                    Image(systemName: "arrow.up").frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveUp)
                .accessibilityLabel(Text("Move \(Text(BriefLabels.section(kind))) up"))
                Button {
                    settings.move(kind, by: 1)
                } label: {
                    Image(systemName: "arrow.down").frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .disabled(!canMoveDown)
                .accessibilityLabel(Text("Move \(Text(BriefLabels.section(kind))) down"))
            }
            if shown.wrappedValue {
                Stepper(value: limit, in: 1...20) {
                    Text("Show up to \(limit.wrappedValue) items")
                }
                .frame(minHeight: 44)
            }
        }
    }
}
