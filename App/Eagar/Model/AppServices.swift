import EagarAI
import EagarCore
import EagarLedger
import EagarSecurity
import EagarStore
import Foundation
import SwiftData
import Synchronization

/// The long-lived services, built once at launch.
struct AppServices: Sendable {
    let stores: EagarStores
    let ledger: PrivacyLedger
    let consents: ConsentRegistry
    let router: AIRouter
    let secrets: any SecretStore
    let catalog: ModelCatalog
    let policy: AppPolicySource

    /// Every SwiftData model in the app. Both stores share one schema; placement is per record.
    static var models: [any PersistentModel.Type] { [LedgerEntry.self, ConsentRecord.self] }

    static func make(inMemory: Bool, secrets: any SecretStore = Keychain()) throws -> AppServices {
        let location: StoreLocation = inMemory
            ? .inMemory
            : .directory(URL.applicationSupportDirectory.appending(path: "Eagar", directoryHint: .isDirectory))
        let stores = try EagarStores(location: location, models: models)
        let ledger = PrivacyLedger(stores: stores, authenticator: DeviceOwnerAuthenticator())
        let consents = ConsentRegistry(stores: stores)
        let catalog = try ModelCatalog.bundled()
        let policy = AppPolicySource(consents: consents, ledger: ledger)
        let router = AIRouter(
            providers: [AppleOnDeviceProvider(), AnthropicProvider(secrets: secrets)],
            ledger: ledger,
            policy: policy,
            catalog: catalog
        )
        return AppServices(
            stores: stores, ledger: ledger, consents: consents, router: router,
            secrets: secrets, catalog: catalog, policy: policy
        )
    }
}

/// Builds the router's policy for each request from consents and the spend cap. M0 has no
/// data sources yet, so no source modes are registered (unknown sources fail closed).
final class AppPolicySource: PolicySource {
    private let consents: ConsentRegistry
    private let ledger: PrivacyLedger
    private let cap = Mutex<Int64?>(nil)

    init(consents: ConsentRegistry, ledger: PrivacyLedger) {
        self.consents = consents
        self.ledger = ledger
    }

    func setMonthlyCap(microUSD: Int64?) {
        cap.withLock { $0 = microUSD }
    }

    var monthlyCapMicroUSD: Int64? { cap.withLock { $0 } }

    func snapshot() async throws -> PolicySnapshot {
        let meter = SpendMeter(monthlyCapMicroUSD: monthlyCapMicroUSD)
        let paused = meter.isCapReached(try await ledger.records(), now: Date())
        return PolicySnapshot(consents: try await consents.active(), cloudPaused: paused)
    }
}
