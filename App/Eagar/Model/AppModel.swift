import EagarAI
import EagarBrief
import EagarCore
import EagarLedger
import EagarSecurity
import Foundation
import Observation
import WidgetKit

/// UI state: the BYOK key, the key test, the privacy ledger and the spend meter (M0), and the
/// calendars, deadlines and Brief through ``planner`` (M1).
@MainActor
@Observable
final class AppModel {
    enum KeyTestState: Equatable {
        case idle
        case running
        case finished(KeyTester.Outcome)
    }

    let services: AppServices
    let planner: PlannerModel
    /// Trials and subscriptions (M2).
    let money: MoneyModel
    /// Keep in touch (M2).
    let people: PeopleModel
    private(set) var maskedKey: String?
    private(set) var keyTestState: KeyTestState = .idle
    private(set) var records: [LedgerRecord] = []
    private(set) var summary: LedgerSummary?
    private(set) var spend: SpendMeter.Report?
    /// The most recent failure, shown in an alert. Never contains content or secrets.
    var failure: AppFailure?

    private let defaults: UserDefaults
    private let log = EagarLog(.app)
    private static let capKey = "spend.monthlyCapMicroUSD"

    init(services: AppServices, defaults: UserDefaults = .standard, clock: any EagarClock = SystemClock(), calendar: Calendar = .current) {
        self.services = services
        self.defaults = defaults
        planner = PlannerModel(services: services, defaults: defaults, clock: clock, calendar: calendar)
        money = MoneyModel(services: services, clock: clock, calendar: calendar)
        people = PeopleModel(services: services, planner: planner, defaults: defaults, clock: clock, calendar: calendar)
        let cap = defaults.object(forKey: Self.capKey) as? Int64
        services.policy.setMonthlyCap(microUSD: cap)
        loadKeyState()
        money.onChange = { [weak self] in self?.applySources() }
        people.onChange = { [weak self] in self?.applySources() }
    }

    // MARK: Activation and the brief's sources (M2)

    /// Launch and scene activation: calendars, deadlines and the brief first, then trials and
    /// people, then the brief again with their sections.
    func appBecameActive() async {
        await planner.appBecameActive()
        await money.refresh()
        await people.refresh()
        applySources()
        await planner.scheduleBriefNotifications()
    }

    /// A calendar change or pull to refresh.
    func refresh() async {
        await planner.refresh()
        await money.load()
        await people.refresh()
        applySources()
    }

    /// Hands trials (and their cancel-by deadlines) and nudges to the planner and recomposes
    /// the brief.
    func applySources() {
        planner.trialDeadlines = money.deadlineRows
        planner.sources = BriefSources(trials: money.briefTrials, subscriptionSummary: money.briefSummary, nudges: people.briefNudges)
        planner.composeBrief()
    }

    var catalog: ModelCatalog { services.catalog }

    // MARK: Kill switch (FR-CORE-07)

    /// Mirrors the shared kill-switch state; the router is halted while it is on.
    private(set) var killSwitchEngaged = false
    private let killSwitch: KillSwitchState = EagarAppGroup.killSwitch
    static let killSwitchPollInterval: Duration = .milliseconds(500)

    /// Turns the kill switch on or off from inside the app (Settings).
    func setKillSwitch(_ engaged: Bool) async {
        killSwitch.set(engaged: engaged)
        ControlCenter.shared.reloadControls(ofKind: "app.eagar.killSwitch")
        await applyKillSwitch(engaged)
    }

    /// Follows changes made by the Control Centre control or a Shortcut while the app runs.
    /// Polls twice a second, well inside the 1-second budget, and only while the app is open.
    func watchKillSwitch() async {
        while !Task.isCancelled {
            let engaged = killSwitch.isEngaged
            if engaged != killSwitchEngaged { await applyKillSwitch(engaged) }
            try? await Task.sleep(for: Self.killSwitchPollInterval)
        }
    }

    private func applyKillSwitch(_ engaged: Bool) async {
        killSwitchEngaged = engaged
        if engaged { await services.router.halt() } else { await services.router.resume() }
    }

    // MARK: Sync (BD-02)

    /// Starts personal sync on team-signed builds (no-op otherwise).
    func startSync() async {
        guard let sync = services.sync else { return }
        await sync.start()
        await sync.syncLocalChanges()
        syncPausedForAccountChange = await sync.coordinator.isPausedForAccountChange
    }

    /// True after an iCloud sign-out or account switch, until Mark confirms (D-018).
    private(set) var syncPausedForAccountChange = false
    var syncAvailable: Bool { services.sync != nil }

    func confirmICloudAccount() async {
        await services.sync?.confirmAccountAndStart()
        syncPausedForAccountChange = false
    }

    // MARK: Claude key (FR-AI-07)

    var hasKey: Bool { maskedKey != nil }

    func saveKey(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try services.secrets.set(Secret(trimmed), for: .anthropicAPIKey)
            keyTestState = .idle
            loadKeyState()
        } catch {
            log.error("saving the Claude key failed: \(error)")
            failure = .keychain
        }
    }

    func removeKey() {
        do {
            try services.secrets.delete(.anthropicAPIKey)
            keyTestState = .idle
            loadKeyState()
        } catch {
            log.error("removing the Claude key failed: \(error)")
            failure = .keychain
        }
    }

    func testKey() async {
        keyTestState = .running
        let outcome = await KeyTester.run(using: services.router)
        keyTestState = .finished(outcome)
        await refreshLedger()
    }

    private func loadKeyState() {
        do {
            maskedKey = try services.secrets.get(.anthropicAPIKey)?.masked
        } catch {
            log.error("reading the Claude key failed: \(error)")
            maskedKey = nil
            failure = .keychain
        }
    }

    // MARK: Ledger (FR-PRIV-05, 06, 08)

    func refreshLedger() async {
        do {
            records = try await services.ledger.records()
            summary = try await services.ledger.summary()
            spend = SpendMeter(monthlyCapMicroUSD: monthlyCapMicroUSD).report(records, now: Date())
        } catch {
            log.error("reading the ledger failed: \(error)")
            failure = .ledgerRead
        }
    }

    func exportLedger(_ records: [LedgerRecord], as format: LedgerExport.FileFormat, includePayloads: Bool) -> Data? {
        do {
            return try LedgerExport.export(records, as: format, includePayloads: includePayloads, exportedAt: Date())
        } catch {
            log.error("ledger export failed: \(error)")
            failure = .export
            return nil
        }
    }

    func eraseLedger(before cutoff: Date) async {
        do {
            _ = try await services.ledger.erase(
                before: cutoff,
                reason: String(localized: "Confirm that you want to erase privacy ledger entries.")
            )
        } catch .authenticationFailed {
            failure = .authentication
        } catch {
            log.error("ledger erase failed: \(error)")
            failure = .ledgerWrite
        }
        await refreshLedger()
    }

    // MARK: Spend (FR-AI-09)

    var monthlyCapMicroUSD: Int64? { services.policy.monthlyCapMicroUSD }

    func setMonthlyCap(dollars: Decimal?) {
        let micro = dollars.map { NSDecimalNumber(decimal: $0 * 1_000_000).int64Value }
        services.policy.setMonthlyCap(microUSD: micro)
        if let micro { defaults.set(micro, forKey: Self.capKey) } else { defaults.removeObject(forKey: Self.capKey) }
        spend = SpendMeter(monthlyCapMicroUSD: micro).report(records, now: Date())
    }

    var isCapReached: Bool {
        SpendMeter(monthlyCapMicroUSD: monthlyCapMicroUSD).isCapReached(records, now: Date())
    }
}

/// User-facing failures. Messages live in the String Catalog.
enum AppFailure: Identifiable, Equatable {
    case keychain, ledgerRead, ledgerWrite, export, authentication

    var id: Self { self }

    var message: LocalizedStringResource {
        switch self {
        case .keychain: "Eagar could not use the Keychain on this device. On a Mac, the app must be signed for Keychain access."
        case .ledgerRead: "Eagar could not read the privacy ledger."
        case .ledgerWrite: "Eagar could not update the privacy ledger."
        case .export: "Eagar could not export the privacy ledger."
        case .authentication: "Authentication was cancelled or failed, so nothing was erased."
        }
    }
}
