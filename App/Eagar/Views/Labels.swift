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
