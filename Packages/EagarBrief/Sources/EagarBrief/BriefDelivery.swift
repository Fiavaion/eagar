import Foundation

/// When to deliver a brief (FR-BRIEF-02, BD-21): the first breakpoint at or after the slot time
/// (end of an event, a gap of 15+ minutes, or the app being opened), never later than 45 minutes
/// after the slot.
public enum BriefDelivery {
    public static let maximumDeferral: TimeInterval = 45 * 60

    /// - Parameters:
    ///   - slotTime: the slot's time today.
    ///   - breakpoints: breakpoint instants from the availability engine, any order.
    ///   - appOpenedAt: when the app came to the foreground, if it did after the slot.
    public static func deliveryTime(slotTime: Date, breakpoints: [Date], appOpenedAt: Date? = nil) -> Date {
        let deadline = slotTime.addingTimeInterval(maximumDeferral)
        let candidates = (breakpoints + (appOpenedAt.map { [$0] } ?? []))
            .filter { $0 >= slotTime && $0 <= deadline }
        return candidates.min() ?? deadline
    }

    /// Whether the brief should be shown now: the delivery time has passed and the brief for this
    /// slot hasn't been delivered yet.
    public static func isDue(now: Date, slotTime: Date, breakpoints: [Date], appOpenedAt: Date?, alreadyDelivered: Bool) -> Bool {
        !alreadyDelivered && now >= deliveryTime(slotTime: slotTime, breakpoints: breakpoints, appOpenedAt: appOpenedAt)
    }
}
