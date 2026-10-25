import EagarCore
import Testing
@testable import EagarAI

/// The §7.4 policy table, transcribed row by row as an independent oracle. Deliberately
/// written differently from `PolicyEngine` (one rule per cell) so a shared mistake is unlikely.
enum PolicyOracle {
    static func permits(_ tier: Tier, _ input: PolicyInput, _ s: PolicySettings) -> Bool {
        // Row: any class from a rulesOnly source -> nothing (FR-AI-03, B-14).
        if input.mode == .rulesOnly { return false }
        // localAI sources never leave Mark's devices, except Meitheal once Mark declares it local.
        if input.mode == .localAI {
            switch tier {
            case .onDevice, .macLocal: break
            case .selfHostedInstitutional: if !s.meithealIsLocal { return false }
            case .applePCC, .anthropicCloud: return false
            }
        }
        switch (input.dataClass, tier) {
        case (.college, .onDevice), (.college, .macLocal): return true
        case (.college, .applePCC), (.college, .anthropicCloud): return false
        case (.college, .selfHostedInstitutional): return s.meithealIsLocal

        case (.personal, .onDevice), (.personal, .macLocal): return true
        case (.personal, .applePCC): return input.kind == .derivedItem || s.applePCCForRawPersonal
        case (.personal, .selfHostedInstitutional): return s.meithealPersonalEnabled
        case (.personal, .anthropicCloud): return input.consentedTiers.contains(.anthropicCloud)

        case (.approvedProfile, _), (.publicContent, _): return true
        }
    }
}

private let allSettings: [PolicySettings] = [false, true].flatMap { a in [false, true].flatMap { b in [false, true].map { c in
    PolicySettings(meithealIsLocal: a, meithealPersonalEnabled: b, applePCCForRawPersonal: c)
} } }

private let allInputs: [PolicyInput] = DataClass.allCases.flatMap { dataClass in
    ContentKind.allCases.flatMap { kind in
        ProcessingMode.allCases.flatMap { mode in
            [Set<Tier>(), [.anthropicCloud]].map { consent in
                PolicyInput(dataClass: dataClass, kind: kind, mode: mode, consentedTiers: consent)
            }
        }
    }
}

struct PolicyEngineTests {
    /// Every (DataClass × ContentKind × ProcessingMode × consent × settings × Tier) cell matches §7.4.
    @Test func everyCombinationMatchesTheTable() {
        var cells = 0
        for settings in allSettings {
            for input in allInputs {
                let allowed = PolicyEngine.allowedTiers(for: input, settings: settings)
                for tier in Tier.allCases {
                    #expect(allowed.contains(tier) == PolicyOracle.permits(tier, input, settings),
                            "\(input.dataClass) \(input.kind) \(input.mode) consent=\(input.consentedTiers) \(settings) \(tier)")
                    cells += 1
                }
            }
        }
        #expect(cells == 4 * 2 * 3 * 2 * 8 * 5)
    }

    @Test func defaultsKeepCollegeOnMarksDevices() {
        let input = PolicyInput(dataClass: .college, kind: .rawBody, mode: .localAI, consentedTiers: Set(Tier.allCases))
        #expect(PolicyEngine.allowedTiers(for: input, settings: PolicySettings()) == [.onDevice, .macLocal])
    }

    /// B-14 (unit form): no locality at all for any input from a rulesOnly source.
    @Test(arguments: DataClass.allCases)
    func Boundary_B14_rulesOnlyPermitsNothing(dataClass: DataClass) {
        for settings in allSettings {
            for kind in ContentKind.allCases {
                let input = PolicyInput(dataClass: dataClass, kind: kind, mode: .rulesOnly, consentedTiers: Set(Tier.allCases))
                #expect(PolicyEngine.allowedTiers(for: input, settings: settings).isEmpty)
            }
        }
    }

    @Test func requestIsIntersectionOfInputs() {
        let personal = PolicyInput(dataClass: .personal, kind: .derivedItem, mode: .cloudAllowed, consentedTiers: [.anthropicCloud])
        let publicItem = PolicyInput(dataClass: .publicContent, kind: .derivedItem, mode: .cloudAllowed)
        let college = PolicyInput(dataClass: .college, kind: .derivedItem, mode: .localAI)
        #expect(PolicyEngine.allowedTiers(for: [personal, publicItem], settings: PolicySettings()).contains(.anthropicCloud))
        #expect(PolicyEngine.allowedTiers(for: [personal, publicItem, college], settings: PolicySettings()) == [.onDevice, .macLocal])
        #expect(PolicyEngine.allowedTiers(for: [], settings: PolicySettings()) == Set(Tier.allCases))
    }

    @Test func cloudPauseRemovesClaudeOnly() {
        let publicItem = PolicyInput(dataClass: .publicContent, kind: .derivedItem, mode: .cloudAllowed)
        let allowed = PolicyEngine.allowedTiers(for: [publicItem], settings: PolicySettings(), cloudPaused: true)
        #expect(allowed == Set(Tier.allCases).subtracting([.anthropicCloud]))
    }

    @Test func blockReasons() {
        let s = PolicySettings()
        let college = PolicyInput(dataClass: .college, kind: .rawBody, mode: .localAI)
        let rulesOnly = PolicyInput(dataClass: .personal, kind: .rawBody, mode: .rulesOnly)
        let personal = PolicyInput(dataClass: .personal, kind: .rawBody, mode: .cloudAllowed)
        let publicItem = PolicyInput(dataClass: .publicContent, kind: .derivedItem, mode: .cloudAllowed)
        #expect(PolicyEngine.blockReason(for: .anthropicCloud, inputs: [college], settings: s) == .collegeBoundary)
        #expect(PolicyEngine.blockReason(for: .onDevice, inputs: [rulesOnly, college], settings: s) == .rulesOnlySource)
        #expect(PolicyEngine.blockReason(for: .anthropicCloud, inputs: [personal], settings: s) == .consentRequired)
        #expect(PolicyEngine.blockReason(for: .applePCC, inputs: [personal], settings: s) == .tierDisabled)
        #expect(PolicyEngine.blockReason(for: .anthropicCloud, inputs: [publicItem], settings: s, cloudPaused: true) == .cloudPaused)
        #expect(PolicyEngine.blockReason(for: .onDevice, inputs: [publicItem], settings: s) == nil)
    }

    @Test func snapshotFailsClosedForUnknownSources() {
        let known = SourceID()
        let snapshot = PolicySnapshot(sourceModes: [known: .cloudAllowed])
        #expect(snapshot.mode(for: known) == .cloudAllowed)
        #expect(snapshot.mode(for: SourceID()) == .rulesOnly)
        #expect(snapshot.mode(for: nil) == .cloudAllowed)
    }
}
