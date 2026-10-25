import EagarBrief
import EagarCore
import EagarLedger
import SwiftUI

/// Where a call was processed, as a shape plus text so colour is never the only signal
/// (FR-AI-12, NFR-A11Y-01).
struct TierBadge: View {
    let tier: Tier

    var body: some View {
        Label {
            Text(Self.name(tier))
        } icon: {
            Image(systemName: Self.symbol(tier))
        }
        .accessibilityLabel(Text("Processed: \(Self.name(tier))"))
    }

    static func name(_ tier: Tier) -> LocalizedStringResource {
        switch tier {
        case .onDevice: "On this device"
        case .macLocal: "On Mac"
        case .applePCC: "Apple PCC"
        case .selfHostedInstitutional: "Meitheal (NCAD)"
        case .anthropicCloud: "Claude"
        }
    }

    static func symbol(_ tier: Tier) -> String {
        switch tier {
        case .onDevice: "iphone"
        case .macLocal: "desktopcomputer"
        case .applePCC: "lock.icloud"
        case .selfHostedInstitutional: "server.rack"
        case .anthropicCloud: "cloud"
        }
    }
}

enum DataClassLabel {
    static func name(_ dataClass: DataClass) -> LocalizedStringResource {
        switch dataClass {
        case .college: "College"
        case .personal: "Personal"
        case .approvedProfile: "Approved profile"
        case .publicContent: "Public"
        }
    }
}

enum LedgerLabels {
    static func kind(_ kind: LedgerEventKind) -> LocalizedStringResource {
        switch kind {
        case .modelCall: "Model call"
        case .blocked: "Blocked attempt"
        case .keyTest: "Key test"
        case .purge: "Purge"
        case .mcpCall: "MCP call"
        case .pushRegistration: "Push registration"
        case .killSwitch: "Kill switch"
        case .erase: "Ledger erased"
        }
    }

    static func outcome(_ outcome: LedgerOutcome) -> LocalizedStringResource {
        switch outcome {
        case .pending: "Pending"
        case .succeeded: "Succeeded"
        case .failed: "Failed"
        case .blocked: "Blocked"
        case .notApplicable: "Recorded"
        }
    }
}

/// The boundary badge for college items (BD-04, NFR-A11Y-01): a house for "stays on your
/// devices" plus text, so colour is never the only signal.
struct BoundaryBadge: View {
    var body: some View {
        Label {
            Text("College")
        } icon: {
            Image(systemName: "house.fill")
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .overlay(Capsule().strokeBorder(.secondary))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("College, stays on your devices"))
        .accessibilityIdentifier("badge.college")
    }
}

enum BriefLabels {
    static func section(_ kind: BriefSectionKind) -> LocalizedStringResource {
        switch kind {
        case .overdue: "Overdue"
        case .today: "Today"
        case .deadlines: "Coming up"
        case .loans: "Loans due"
        case .trials: "Trials about to bill"
        case .mail: "Mail"
        case .approvals: "Waiting for approval"
        case .waiting: "Waiting on others"
        case .keepInTouch: "Keep in touch"
        case .media: "Listening and watching"
        }
    }

    static func slot(_ kind: BriefSlot.Kind) -> LocalizedStringResource {
        switch kind {
        case .morning: "Morning brief"
        case .midday: "Midday brief"
        case .endOfDay: "End-of-day brief"
        }
    }

    static func phrasing(_ mode: BriefPhrasingMode) -> LocalizedStringResource {
        switch mode {
        case .off: "Off"
        case .localOnly: "On your devices only"
        case .claudeForPersonal: "Claude for personal items"
        }
    }

    static func state(_ action: BriefAction) -> LocalizedStringResource {
        switch action {
        case .open: "Opened"
        case .done: "Done"
        case .snooze: "Snoozed"
        case .reschedule: "Rescheduled"
        case .dismiss: "Dismissed"
        }
    }

    /// Reminder offsets offered for deadlines, in minutes before the due time.
    static let offsetChoices = [0, 15, 60, 120, 1440, 2880, 10080]

    static func offset(_ minutes: Int) -> LocalizedStringResource {
        switch minutes {
        case 0: "At the due time"
        case 15: "15 minutes before"
        case 60: "1 hour before"
        case 120: "2 hours before"
        case 1440: "1 day before"
        case 2880: "2 days before"
        case 10080: "1 week before"
        default: "\(minutes) minutes before"
        }
    }
}
