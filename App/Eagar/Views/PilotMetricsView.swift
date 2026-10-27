import SwiftUI

/// Pilot metrics (FR-GOV-01): manual weekly Screen Time entries for SM1 (Appendix D, D1).
/// Derived metrics from the ledgers join in M3.
struct PilotMetricsView: View {
    let metrics: PilotMetricsModel
    @State private var week = Date()
    @State private var minutes = 0
    @State private var pickups = 0

    var body: some View {
        Form {
            Section {
                DatePicker("Week of", selection: $week, displayedComponents: .date)
                LabeledContent("Minutes") {
                    TextField("Minutes", value: $minutes, format: .number)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                        .accessibilityIdentifier("pilot.minutes")
                }
                LabeledContent("Pickups") {
                    TextField("Pickups", value: $pickups, format: .number)
                        .multilineTextAlignment(.trailing)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                Button("Save week") {
                    metrics.record(week: week, minutes: minutes, pickups: pickups)
                }
                .frame(minHeight: 44)
                .accessibilityIdentifier("pilot.save")
            } header: {
                Text("Add a week")
            } footer: {
                Text("From Screen Time, add the total minutes and pickups for Gmail, Mail, Outlook, Calendar, Podcasts, YouTube, Canvas and Safari (cdbooking). Two weeks before the mail milestone make the baseline.")
            }
            Section {
                if metrics.entries.isEmpty {
                    Text("No weeks yet.").foregroundStyle(.secondary)
                } else {
                    if let average = metrics.averageMinutes {
                        LabeledContent("Average per week") { Text("\(average) min") }
                    }
                    ForEach(metrics.entries) { entry in
                        HStack {
                            Text("Week of \(entry.weekStart, format: .dateTime.day().month().year())")
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("\(entry.minutes) min")
                                if let pickups = entry.pickups {
                                    Text("\(pickups) pickups").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .swipeActions {
                            Button("Delete", role: .destructive) { metrics.delete(entry) }
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) { metrics.delete(entry) }
                        }
                        .accessibilityAction(named: Text("Delete")) { metrics.delete(entry) }
                    }
                }
            } header: {
                Text("Screen Time (SM1)")
            } footer: {
                Text("Stored on this device only. Numbers only, no app content.")
            }
        }
        .navigationTitle(Text("Pilot metrics"))
        .onAppear { week = metrics.lastWeekStart }
    }
}
