import EagarCore
import Foundation

/// A secret value (API key, OAuth token, app-specific password, feed token).
///
/// Deliberately not `LogSafe`, `Codable` or `Equatable` to strings, and its descriptions are
/// redacted, so it cannot reach logs, exports or SwiftData by accident (invariant 6).
public struct Secret: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    private let value: String

    public init(_ value: String) {
        self.value = value
    }

    /// The raw value. Call only at the point of use (an HTTP header, a Keychain write).
    public func reveal() -> String { value }

    /// The value with all but the last four characters masked, for display after entry (FR-AI-07).
    public var masked: String {
        guard value.count > 8 else { return String(repeating: "•", count: value.count) }
        return String(repeating: "•", count: 8) + value.suffix(4)
    }

    public var isEmpty: Bool { value.isEmpty }

    public var description: String { "<redacted>" }
    public var debugDescription: String { "<redacted>" }
    public var customMirror: Mirror { Mirror(self, children: []) }
}

/// Names of the secrets Eagar stores. One Keychain item each.
public struct SecretKey: Hashable, Sendable {
    public let account: String

    public init(account: String) {
        self.account = account
    }

    /// Mark's Claude API key for this device (BD-07).
    public static let anthropicAPIKey = SecretKey(account: "anthropic.apiKey")

    /// The per-user cdbooking iCal feed URL, which embeds the `feed_token` (FR-BOOK-01, Appendix E.2).
    public static func cdbookingFeedURL(_ source: SourceID) -> SecretKey {
        SecretKey(account: "cdbooking.\(source.rawValue.uuidString).feedURL")
    }

    /// The cdbooking `api_token` bearer token (FR-BOOK-01, Appendix E.2).
    public static func cdbookingAPIToken(_ source: SourceID) -> SecretKey {
        SecretKey(account: "cdbooking.\(source.rawValue.uuidString).apiToken")
    }

    /// The Canvas calendar feed URL, a bearer secret (FR-CANVAS-01).
    public static func canvasFeedURL(_ source: SourceID) -> SecretKey {
        SecretKey(account: "canvas.\(source.rawValue.uuidString).feedURL")
    }
}
