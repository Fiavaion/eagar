import Foundation
import Security
import EagarCore
import Testing
@testable import EagarSecurity

/// In-memory backend that records every attribute dictionary it receives.
// SAFETY: all mutable state is guarded by `lock`; test-only fake holding CF attribute dictionaries.
final class RecordingKeychainBackend: KeychainBackend, @unchecked Sendable {
    struct State {
        var items: [String: Data] = [:]
        var added: [[String: Any]] = []
        var queries: [[String: Any]] = []
    }

    private let lock = NSLock()
    private var _state = State()

    func withState<R>(_ body: (inout State) -> R) -> R {
        lock.lock()
        defer { lock.unlock() }
        return body(&_state)
    }

    private static func account(_ query: [String: Any]) -> String { query[kSecAttrAccount as String] as! String }

    func add(_ attributes: [String: Any]) -> OSStatus {
        withState {
            $0.added.append(attributes)
            $0.items[Self.account(attributes)] = attributes[kSecValueData as String] as? Data
        }
        return errSecSuccess
    }

    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        withState {
            $0.queries.append(query)
            guard $0.items[Self.account(query)] != nil else { return errSecItemNotFound }
            $0.items[Self.account(query)] = attributes[kSecValueData as String] as? Data
            return errSecSuccess
        }
    }

    func copyMatching(_ query: [String: Any]) -> (OSStatus, AnyObject?) {
        withState {
            $0.queries.append(query)
            guard let data = $0.items[Self.account(query)] else { return (errSecItemNotFound, nil) }
            return (errSecSuccess, data as NSData)
        }
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        withState {
            $0.queries.append(query)
            return $0.items.removeValue(forKey: Self.account(query)) == nil ? errSecItemNotFound : errSecSuccess
        }
    }
}

struct KeychainTests {
    /// Invariant 6 / FR-AI-07: the BYOK key is stored this-device-only and never synchronizable.
    @Test func newItemUsesThisDeviceOnlyNonSynchronizableAttributes() throws {
        let backend = RecordingKeychainBackend()
        let keychain = Keychain(backend: backend)
        try keychain.set(Secret("test-canary-key-0001"), for: .anthropicAPIKey)

        let added = try #require(backend.withState { $0.added.first })
        #expect(added[kSecClass as String] as! CFString == kSecClassGenericPassword)
        #expect(added[kSecAttrAccessible as String] as! CFString == kSecAttrAccessibleWhenUnlockedThisDeviceOnly)
        #expect((added[kSecAttrSynchronizable as String] as! CFBoolean) == kCFBooleanFalse)
        #expect(added[kSecUseDataProtectionKeychain as String] as? Bool == true)
        #expect(added[kSecAttrAccount as String] as? String == "anthropic.apiKey")
    }

    @Test func everyQueryPinsSynchronizableFalse() throws {
        let backend = RecordingKeychainBackend()
        let keychain = Keychain(backend: backend)
        try keychain.set(Secret("one"), for: .anthropicAPIKey)
        _ = try keychain.get(.anthropicAPIKey)
        try keychain.delete(.anthropicAPIKey)
        let queries = backend.withState { $0.queries }
        #expect(queries.count == 3)
        for query in queries {
            #expect((query[kSecAttrSynchronizable as String] as! CFBoolean) == kCFBooleanFalse)
        }
    }

    @Test func roundTripUpdateAndDelete() throws {
        let keychain = Keychain(backend: RecordingKeychainBackend())
        #expect(try keychain.get(.anthropicAPIKey) == nil)
        try keychain.set(Secret("first"), for: .anthropicAPIKey)
        try keychain.set(Secret("second"), for: .anthropicAPIKey)
        #expect(try keychain.get(.anthropicAPIKey)?.reveal() == "second")
        try keychain.delete(.anthropicAPIKey)
        #expect(try keychain.get(.anthropicAPIKey) == nil)
        try keychain.delete(.anthropicAPIKey) // deleting a missing item is not an error
    }

    @Test func secretNeverDescribesItsValue() {
        let secret = Secret("test-canary-key-0002")
        #expect("\(secret)" == "<redacted>")
        #expect(String(reflecting: secret) == "<redacted>")
        var dumped = ""
        dump(secret, to: &dumped)
        #expect(!dumped.contains("canary"))
        #expect(secret.masked == "••••••••0002")
        #expect(Secret("short").masked == "•••••")
    }

    /// Feed secrets get one Keychain item per source and per secret (FR-BOOK-01, FR-CANVAS-01).
    @Test func feedSecretKeysAreDistinctPerSource() {
        let a = SourceID(), b = SourceID()
        let keys = [
            SecretKey.cdbookingFeedURL(a), .cdbookingAPIToken(a), .canvasFeedURL(a),
            .cdbookingFeedURL(b), .cdbookingAPIToken(b), .canvasFeedURL(b), .anthropicAPIKey,
        ]
        #expect(Set(keys).count == keys.count)
        #expect(SecretKey.cdbookingAPIToken(a) == .cdbookingAPIToken(a))
    }
}
