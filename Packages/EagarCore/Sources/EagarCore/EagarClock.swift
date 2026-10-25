import Foundation

/// Source of wall-clock time. Inject it so tests can use a fixed clock.
///
/// Named `EagarClock` rather than `Clock` to avoid shadowing `Swift.Clock` in importing modules.
public protocol EagarClock: Sendable {
    func now() -> Date
}

/// The real clock.
public struct SystemClock: EagarClock {
    public init() {}
    public func now() -> Date { Date() }
}
