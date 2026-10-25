import EagarCore
import EagarSecurity
import Foundation
import Testing
@testable import EagarTestSupport

struct EagarTestSupportTests {
    @Test func fixedClockAdvances() {
        let clock = FixedClock(Date(timeIntervalSince1970: 0))
        clock.advance(by: 60)
        #expect(clock.now() == Date(timeIntervalSince1970: 60))
    }

    @Test func stubAuthenticator() async {
        await #expect(throws: SecurityError.authenticationCancelled) {
            try await StubAuthenticator(succeeds: false).authenticate(reason: "x")
        }
        _ = try? await StubAuthenticator().authenticate(reason: "x")
    }

    @Test func secretStoreRoundTrip() throws {
        let store = InMemorySecretStore()
        try store.set(Secret("v"), for: .anthropicAPIKey)
        #expect(try store.get(.anthropicAPIKey)?.reveal() == "v")
        try store.delete(.anthropicAPIKey)
        #expect(try store.get(.anthropicAPIKey) == nil)
    }

    @Test func reexportsRecordingProvider() {
        #expect(RecordingProvider.oneOfEach().count == Tier.allCases.count)
    }
}
