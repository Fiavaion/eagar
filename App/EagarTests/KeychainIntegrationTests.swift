import EagarSecurity
import Foundation
import Security
import Testing

/// Reads back real Keychain attributes (invariant 6, M0 acceptance). Always runs on the iOS
/// simulator. On macOS the data-protection keychain needs the Keychain Sharing entitlement,
/// which only team-signed builds carry (D-011), so the test runs there when it is present.
enum KeychainEntitlement {
    static var available: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return SecTaskCopyValueForEntitlement(task, "keychain-access-groups" as CFString, nil) != nil
        #else
        return true
        #endif
    }
}

struct KeychainIntegrationTests {
    @Test(.enabled(if: KeychainEntitlement.available, "needs a team-signed build on macOS"))
    func storedKeyIsThisDeviceOnlyAndNotSynchronizable() throws {
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
