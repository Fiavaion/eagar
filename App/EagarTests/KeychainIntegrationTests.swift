import EagarSecurity
import Foundation
import Security
import Testing

/// Reads back real Keychain attributes (invariant 6, M0 acceptance). Runs on the iOS simulator,
/// where the hosted test app has Keychain access without a signing team; on macOS the
/// data-protection keychain needs a signed build, so the attribute dictionaries are covered by
/// EagarSecurity's unit tests and this check runs on Mark's signed build.
#if os(iOS)
struct KeychainIntegrationTests {
    @Test func storedKeyIsThisDeviceOnlyAndNotSynchronizable() throws {
        let keychain = Keychain(service: "app.eagar.tests.\(UUID().uuidString)")
        defer { try? keychain.delete(.anthropicAPIKey) }
        try keychain.set(Secret("test-canary-key-ios-0001"), for: .anthropicAPIKey)
        #expect(try keychain.get(.anthropicAPIKey)?.reveal() == "test-canary-key-ios-0001")

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychain.service,
            kSecAttrAccount as String: SecretKey.anthropicAPIKey.account,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        #expect(SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess)
        let items = try #require(result as? [[String: Any]])
        #expect(items.count == 1)
        let attributes = try #require(items.first)
        #expect(attributes[kSecAttrAccessible as String] as? String == kSecAttrAccessibleWhenUnlockedThisDeviceOnly as String)
        #expect((attributes[kSecAttrSynchronizable as String] as? NSNumber)?.boolValue != true)
    }
}
#endif
