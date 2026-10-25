import EagarAI
import EagarSecurity
import Foundation
import Synchronization
import Testing
@testable import Eagar

/// Local fake. The app tests deliberately don't link EagarTestSupport: it would load a second
/// copy of EagarAI (and its SwiftData models) beside the host app's copy.
final class MemorySecrets: SecretStore {
    private let values = Mutex<[String: String]>([:])
    func set(_ secret: Secret, for key: SecretKey) throws(SecurityError) { values.withLock { $0[key.account] = secret.reveal() } }
    func get(_ key: SecretKey) throws(SecurityError) -> Secret? { values.withLock { $0[key.account] }.map(Secret.init) }
    func delete(_ key: SecretKey) throws(SecurityError) { _ = values.withLock { $0.removeValue(forKey: key.account) } }
}

@MainActor
struct AppModelTests {
    private func makeModel() throws -> AppModel {
        let defaults = UserDefaults(suiteName: "eagar.tests.\(UUID().uuidString)")!
        return AppModel(services: try AppServices.make(inMemory: true, secrets: MemorySecrets()), defaults: defaults)
    }

    @Test func savedKeyIsOnlyShownMasked() throws {
        let model = try makeModel()
        #expect(!model.hasKey)
        model.saveKey("  test-canary-key-app-1234  ")
        #expect(model.maskedKey == "••••••••1234")
        model.removeKey()
        #expect(model.maskedKey == nil)
    }

    @Test func keyTestWithoutKeyReportsNoKeyAndSendsNothing() async throws {
        let model = try makeModel()
        await model.testKey()
        #expect(model.keyTestState == .finished(.noKey))
        #expect(model.summary?.offDeviceCalls == 0)
    }

    @Test func spendCapIsStored() throws {
        let model = try makeModel()
        model.setMonthlyCap(dollars: Decimal(string: "5"))
        #expect(model.monthlyCapMicroUSD == 5_000_000)
        model.setMonthlyCap(dollars: nil)
        #expect(model.monthlyCapMicroUSD == nil)
    }

    @Test func modelListIsFromTheCatalogue() throws {
        let model = try makeModel()
        #expect(model.catalog.offeredModels.map(\.id.rawValue).contains("claude-haiku-5-5"))
        #expect(!model.catalog.offeredModels.map(\.id.rawValue).contains("claude-fable-5-1"))
    }
}
