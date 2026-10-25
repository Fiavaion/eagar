@_exported import EagarAITestSupport
import EagarCore
import EagarSecurity
import Foundation
import Synchronization

/// A clock fixed at one instant, or advanced by hand.
public final class FixedClock: EagarClock {
    private let current: Mutex<Date>

    public init(_ date: Date = Date(timeIntervalSince1970: 1_793_000_000)) {
        current = Mutex(date)
    }

    public func now() -> Date { current.withLock { $0 } }

    public func advance(by interval: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(interval) }
    }
}

/// Device-owner authentication that succeeds or fails on demand.
public struct StubAuthenticator: DeviceOwnerAuthenticating {
    public let succeeds: Bool
    public init(succeeds: Bool = true) { self.succeeds = succeeds }

    public func authenticate(reason: String) async throws(SecurityError) -> AuthenticationProof {
        guard succeeds else { throw .authenticationCancelled }
        return AuthenticationProof(at: Date(), method: .passcode)
    }
}

/// An in-memory `SecretStore`.
public final class InMemorySecretStore: SecretStore {
    private let values = Mutex<[String: String]>([:])

    public init() {}

    public func set(_ secret: Secret, for key: SecretKey) throws(SecurityError) {
        values.withLock { $0[key.account] = secret.reveal() }
    }

    public func get(_ key: SecretKey) throws(SecurityError) -> Secret? {
        values.withLock { $0[key.account] }.map(Secret.init)
    }

    public func delete(_ key: SecretKey) throws(SecurityError) {
        _ = values.withLock { $0.removeValue(forKey: key.account) }
    }
}
