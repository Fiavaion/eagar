import Foundation
import LocalAuthentication

/// The result of a successful device-owner authentication.
///
/// Protection comes from the call path, not from this value: APIs that need authentication
/// (ledger erasure, sends) call their injected ``DeviceOwnerAuthenticating`` themselves.
public struct AuthenticationProof: Sendable {
    public let at: Date
    public let method: AuthenticationMethod

    public init(at: Date, method: AuthenticationMethod) {
        self.at = at
        self.method = method
    }
}

public enum AuthenticationMethod: String, Codable, Sendable {
    case biometric, passcode, unknown
}

/// Device-owner authentication (Face ID / Touch ID, falling back to passcode).
/// Used for ledger erasure in M0 and for every send from M3 (BD-11).
public protocol DeviceOwnerAuthenticating: Sendable {
    /// `reason` is shown by the system; pass a localised string.
    func authenticate(reason: String) async throws(SecurityError) -> AuthenticationProof
}

/// The LocalAuthentication implementation.
public struct DeviceOwnerAuthenticator: DeviceOwnerAuthenticating {
    public init() {}

    public func authenticate(reason: String) async throws(SecurityError) -> AuthenticationProof {
        let context = LAContext()
        var availabilityError: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &availabilityError) else {
            throw .authenticationUnavailable
        }
        do {
            try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch let error as LAError where [.userCancel, .appCancel, .systemCancel].contains(error.code) {
            throw .authenticationCancelled
        } catch {
            throw .authenticationFailed
        }
        let method: AuthenticationMethod = switch context.biometryType {
        case .none: .passcode
        case .faceID, .touchID, .opticID: .biometric
        @unknown default: .unknown
        }
        return AuthenticationProof(at: Date(), method: method)
    }
}
