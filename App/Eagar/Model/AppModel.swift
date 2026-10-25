import EagarAI
import EagarCore
import EagarLedger
import EagarSecurity
import Foundation
import Observation

/// UI state for M0: the BYOK key, the key test, the privacy ledger and the spend meter.
@MainActor
@Observable
final class AppModel {
    enum KeyTestState: Equatable {
        case idle
        case running
        case finished(KeyTester.Outcome)
    }

    let services: AppServices
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

    init(services: AppServices, defaults: UserDefaults = .standard) {
        self.services = services
        self.defaults = defaults
        let cap = defaults.object(forKey: Self.capKey) as? Int64
        services.policy.setMonthlyCap(microUSD: cap)
        loadKeyState()
    }

    var catalog: ModelCatalog { services.catalog }

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
