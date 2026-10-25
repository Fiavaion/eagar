import Foundation

/// The global kill switch's persisted state (FR-CORE-07, BD-11).
///
/// Stored in the App Group's defaults so the Control Centre control (an extension) and the app
/// share it. The app observes it and halts the AI router; from M3 it also cancels held sends.
/// Holds only the suite name and opens the defaults on each access, so it is plainly `Sendable`.
public struct KillSwitchState: Sendable {
    public static let key = "killSwitch.engaged"
    /// `nil` means the standard defaults.
    public let suiteName: String?

    public init(suiteName: String?) {
        self.suiteName = suiteName
    }

    private var defaults: UserDefaults { suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard }

    public var isEngaged: Bool { defaults.bool(forKey: Self.key) }

    public func set(engaged: Bool) {
        defaults.set(engaged, forKey: Self.key)
    }
}
