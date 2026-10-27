import EagarBookings
import EagarFeeds
import SwiftUI

/// College feeds in Settings: cdbooking (FR-BOOK-01, 02, 06) and Canvas (FR-CANVAS-01). Shows
/// each feed's health so a failure is never silent, secrets only masked, and a remove action.
struct FeedSettingsSections: View {
    let feeds: FeedsModel

    var body: some View {
        BookingFeedSection(feeds: feeds)
        if let summary = feeds.adminSummary {
            AdminSummarySection(summary: summary)
        }
        CanvasFeedSection(feeds: feeds)
    }
}

private struct BookingFeedSection: View {
    let feeds: FeedsModel
    @State private var feedURL = ""
    @State private var apiToken = ""
    @State private var replacing = false
    @State private var confirmingRemove = false

    var body: some View {
        Section {
            if let source = feeds.booking, !replacing {
                LabeledContent("Feed address") { Text(verbatim: feeds.maskedBookingFeedURL ?? "") }
                LabeledContent("API token") {
                    if let token = feeds.maskedBookingToken { Text(verbatim: token) } else { Text("None") }
                }
                FeedHealthRow(state: source, kind: .cdbooking)
                if source.health == .ok {
                    if feeds.maskedBookingToken == nil {
                        Text("Without an API token, Eagar reads the calendar feed only.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if feeds.lastBookingPath == .iCalendar {
                        Text("The cdbooking API was unavailable, so Eagar used the calendar feed instead.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Text("Active loans: \(feeds.activeLoans.count)")
                FeedActions(
                    feeds: feeds, needsAttention: source.health.needsAttention,
                    onReplace: { replacing = true }, onRemove: { confirmingRemove = true },
                    identifier: "settings.cdbooking"
                )
            } else {
                SecureField("Feed address (https:// or webcal://)", text: $feedURL)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings.cdbooking.feedURL")
                SecureField("API token (optional)", text: $apiToken)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings.cdbooking.token")
                Button(replacing ? "Save" : "Add cdbooking") {
                    Task {
                        if await feeds.connectBooking(feedURL: feedURL, apiToken: apiToken) {
                            feedURL = ""
                            apiToken = ""
                            replacing = false
                        }
                    }
                }
                .frame(minHeight: 44)
                .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("settings.cdbooking.add")
                if replacing {
                    Button("Cancel", role: .cancel) {
                        feedURL = ""
                        apiToken = ""
                        replacing = false
                    }
                    .frame(minHeight: 44)
                }
            }
        } header: {
            HStack {
                Text("Loans (cdbooking)")
                BoundaryBadge()
            }
        } footer: {
            Text("In cdbooking, open your profile and copy your calendar feed and API token. Both are kept in the Keychain on this device. Loans stay on your devices and appear as college deadlines with return reminders 24 hours and 2 hours before they are due.")
        }
        .confirmationDialog("Remove cdbooking?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await feeds.removeBooking() } }
        } message: {
            Text("Your loans, their deadlines and reminders, and the feed address and token are deleted from this device.")
        }
    }
}

private struct CanvasFeedSection: View {
    let feeds: FeedsModel
    @State private var feedURL = ""
    @State private var replacing = false
    @State private var confirmingRemove = false

    var body: some View {
        Section {
            if let source = feeds.canvas, !replacing {
                LabeledContent("Feed address") { Text(verbatim: feeds.maskedCanvasFeedURL ?? "") }
                FeedHealthRow(state: source, kind: .canvas)
                Text("Assignments: \(feeds.canvasAssignmentCount), other events: \(feeds.canvasEventCount)")
                FeedActions(
                    feeds: feeds, needsAttention: source.health.needsAttention,
                    onReplace: { replacing = true }, onRemove: { confirmingRemove = true },
                    identifier: "settings.canvas"
                )
            } else {
                SecureField("Calendar feed address", text: $feedURL)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("settings.canvas.feedURL")
                Button(replacing ? "Save" : "Add Canvas") {
                    Task {
                        if await feeds.connectCanvas(feedURL: feedURL) {
                            feedURL = ""
                            replacing = false
                        }
                    }
                }
                .frame(minHeight: 44)
                .disabled(feedURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("settings.canvas.add")
                if replacing {
                    Button("Cancel", role: .cancel) {
                        feedURL = ""
                        replacing = false
                    }
                    .frame(minHeight: 44)
                }
            }
        } header: {
            HStack {
                Text("Canvas")
                BoundaryBadge()
            }
        } footer: {
            Text("In Canvas, open Calendar and copy the Calendar Feed link. Anyone with the link can read your calendar, so it is kept in the Keychain. Assignment due dates become college deadlines.")
        }
        .confirmationDialog("Remove Canvas?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await feeds.removeCanvas() } }
        } message: {
            Text("Your Canvas items, their deadlines and the feed address are deleted from this device.")
        }
    }
}

/// Refresh now, replace (shown first when the feed needs attention) and remove.
private struct FeedActions: View {
    let feeds: FeedsModel
    let needsAttention: Bool
    let onReplace: () -> Void
    let onRemove: () -> Void
    let identifier: String

    var body: some View {
        Button {
            Task { await feeds.refresh(force: true) }
        } label: {
            if feeds.isRefreshing {
                Label("Refreshing…", systemImage: "arrow.clockwise")
            } else {
                Label("Refresh now", systemImage: "arrow.clockwise")
            }
        }
        .frame(minHeight: 44)
        .disabled(feeds.isRefreshing)
        .accessibilityIdentifier("\(identifier).refresh")
        Button(needsAttention ? "Enter a new address or token" : "Replace address or token", action: onReplace)
            .frame(minHeight: 44)
        Button("Remove", role: .destructive, action: onRemove)
            .frame(minHeight: 44)
            .accessibilityIdentifier("\(identifier).remove")
    }
}

/// A feed's health as text and a symbol, never colour alone (NFR-A11Y-01).
private struct FeedHealthRow: View {
    let state: FeedSourceState
    let kind: FeedKind

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label {
                Text(FeedHealthText.status(state.health, kind: kind))
            } icon: {
                Image(systemName: FeedHealthText.symbol(state.health))
            }
            if let last = state.lastSuccessAt {
                Text("Last updated \(last, format: .relative(presentation: .named))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feed.health")
    }
}

enum FeedHealthText {
    static func status(_ health: FeedHealth, kind: FeedKind) -> LocalizedStringResource {
        switch (health, kind) {
        case (.ok, _): "Working"
        case (.unknown, _): "Not checked yet"
        case (.notConfigured, _): "The feed address is missing. Enter it again."
        case (.unauthorised, .canvas): "Canvas refused this feed address. Copy the current one from Canvas and enter it again."
        case (.unauthorised, _): "Token revoked: cdbooking refused it. Copy a new token from cdbooking and enter it again."
        case (.revoked, .canvas): "This feed address was reset or turned off. Copy the new one from Canvas."
        case (.revoked, _): "Feed revoked. Create a new feed in cdbooking and enter its address again."
        case (.failing, _): "Eagar couldn't refresh this feed. It will try again later."
        }
    }

    static func symbol(_ health: FeedHealth) -> String {
        switch health {
        case .ok: "checkmark.circle"
        case .unknown: "clock"
        case .failing: "exclamationmark.arrow.triangle.2.circlepath"
        case .notConfigured, .unauthorised, .revoked: "exclamationmark.triangle"
        }
    }
}

/// FR-BOOK-06: counts only, with a link to cdbooking. No names or booking details.
private struct AdminSummarySection: View {
    let summary: AdminSummary
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            LabeledContent("Pending approvals") { Text(summary.pendingApprovals, format: .number) }
            LabeledContent("Overdue returns") { Text(summary.overdueReturns, format: .number) }
            Button {
                openURL(summary.deepLink)
            } label: {
                Label("Open cdbooking admin", systemImage: "arrow.up.forward.square")
            }
            .frame(minHeight: 44)
        } header: {
            Text("cdbooking admin")
        } footer: {
            Text("Counts only. Details stay in cdbooking.")
        }
    }
}
