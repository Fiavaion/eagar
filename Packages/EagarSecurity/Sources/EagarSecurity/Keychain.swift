import EagarCore
import Foundation
import Security

/// Errors from Keychain and authentication operations.
public enum SecurityError: Error, Equatable, Sendable, LogSafe {
    case keychain(status: Int32)
    case malformedItem
    case authenticationFailed
    case authenticationCancelled
    case authenticationUnavailable

    public var logDescription: String {
        switch self {
        case let .keychain(status): "keychain(\(status))"
        case .malformedItem: "malformedItem"
        case .authenticationFailed: "authenticationFailed"
        case .authenticationCancelled: "authenticationCancelled"
        case .authenticationUnavailable: "authenticationUnavailable"
        }
    }
}

/// Storage for secrets. The only implementation in the app is ``Keychain``.
public protocol SecretStore: Sendable {
    func set(_ secret: Secret, for key: SecretKey) throws(SecurityError)
    func get(_ key: SecretKey) throws(SecurityError) -> Secret?
    func delete(_ key: SecretKey) throws(SecurityError)
}

/// The raw `SecItem` calls, injectable so the attribute dictionaries can be tested without
/// a signed host app.
public protocol KeychainBackend: Sendable {
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus
    func copyMatching(_ query: [String: Any]) -> (OSStatus, AnyObject?)
    func delete(_ query: [String: Any]) -> OSStatus
}

/// The system Keychain.
public struct SystemKeychainBackend: KeychainBackend {
    public init() {}

    public func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public func update(_ query: [String: Any], _ attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    public func copyMatching(_ query: [String: Any]) -> (OSStatus, AnyObject?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result)
    }

    public func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

/// Generic-password Keychain storage with the attributes invariant 6 requires:
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`, never synchronizable, data-protection keychain.
public struct Keychain: SecretStore {
    /// `kSecAttrService` for every Eagar item.
    public let service: String
    private let backend: any KeychainBackend

    public init(service: String = "app.eagar.secrets", backend: any KeychainBackend = SystemKeychainBackend()) {
        self.service = service
        self.backend = backend
    }

    public func set(_ secret: Secret, for key: SecretKey) throws(SecurityError) {
        let data = Data(secret.reveal().utf8)
        // Re-assert accessibility on update so an older item can never keep weaker attributes.
        let status = backend.update(identity(key), [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ])
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            let addStatus = backend.add(Self.addAttributes(identity: identity(key), data: data))
            guard addStatus == errSecSuccess else { throw .keychain(status: addStatus) }
        default:
            throw .keychain(status: status)
        }
    }

    public func get(_ key: SecretKey) throws(SecurityError) -> Secret? {
        var query = identity(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        let (status, result) = backend.copyMatching(query)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                throw .malformedItem
            }
            return Secret(value)
        case errSecItemNotFound:
            return nil
        default:
            throw .keychain(status: status)
        }
    }

    public func delete(_ key: SecretKey) throws(SecurityError) {
        let status = backend.delete(identity(key))
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status: status) }
    }

    /// The attributes that identify an item. `kSecAttrSynchronizable = false` is part of the
    /// identity so a synchronizable item with the same account can never be read or overwritten.
    func identity(_ key: SecretKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.account,
            kSecAttrSynchronizable as String: kCFBooleanFalse!,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    /// The full attribute set for a new item (invariant 6, BD-07).
    static func addAttributes(identity: [String: Any], data: Data) -> [String: Any] {
        var attributes = identity
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        attributes[kSecValueData as String] = data
        return attributes
    }
}
