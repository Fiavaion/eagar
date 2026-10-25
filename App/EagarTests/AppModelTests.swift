import EagarAI
import EagarTestSupport
import Foundation
import Testing
@testable import Eagar

@MainActor
struct AppModelTests {
    private func makeModel() throws -> AppModel {
        let defaults = UserDefaults(suiteName: "eagar.tests.\(UUID().uuidString)")!
        return AppModel(services: try AppServices.make(inMemory: true, secrets: InMemorySecretStore()), defaults: defaults)
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
