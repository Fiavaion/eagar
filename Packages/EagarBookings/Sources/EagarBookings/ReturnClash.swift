import EagarCalendar
import EagarCore
import Foundation

/// Tunables for the loan-return clash check (FR-BOOK-04).
public struct ReturnClashPolicy: Sendable, Hashable {
    /// Time Mark needs at the returns desk; the return window is `[due − this, due)`.
    public let returnDuration: TimeInterval
    /// How far before the due time to look for an earlier slot.
    public let lookback: TimeInterval
    /// Returns desk opening hours, local time, as whole hours `[open, close)`.
    public let deskOpenHour: Int
    public let deskCloseHour: Int

    public init(returnDuration: TimeInterval = 15 * 60, lookback: TimeInterval = 48 * 3600, deskOpenHour: Int = 9, deskCloseHour: Int = 17) {
        self.returnDuration = max(60, returnDuration)
        self.lookback = max(0, lookback)
        self.deskOpenHour = min(max(0, deskOpenHour), 23)
        self.deskCloseHour = min(max(self.deskOpenHour + 1, deskCloseHour), 24)
    }

    public static let `default` = ReturnClashPolicy()
}

/// A loan whose return window overlaps busy time, with an earlier slot if one exists.
///
/// Carries times and the booking ID only, never titles or event details. Its class is the
/// taint of the loan and every busy block considered, so it is college for a cdbooking loan.
public struct ReturnClash: Sendable, Hashable, Classified {
    public let bookingID: String
    public let dueAt: Date
    /// The busy time overlapping the return window.
    public let clashingIntervals: [DateInterval]
    /// The latest free slot before the due time, inside desk hours and not in the past.
    /// `nil` when there is none: offer the extension page instead.
    public let proposedSlot: DateInterval?
    /// cdbooking's extension request page for this booking (FR-BOOK-04).
    public let extendURL: URL?
    public let dataClass: DataClass
    public var sourceID: SourceID? { nil }
}

/// Deterministic clash detection and earlier-slot proposal (FR-BOOK-04). Pure; no AI, no I/O.
public enum ReturnClashCheck {
    /// Checks one loan against busy blocks (from ``AvailabilityEngine/busyBlocks(for:in:calendar:)``
    /// over a window that covers `policy.lookback` before the due time). Nil when there is no clash
    /// or the booking is not an active loan.
    public static func check(
        _ loan: BookingSnapshot, busy: [BusyBlock], now: Date, calendar: Calendar, policy: ReturnClashPolicy = .default
    ) -> ReturnClash? {
        guard loan.booking.isActiveLoan, let due = loan.booking.due else { return nil }
        return check(
            bookingID: loan.booking.id, dueAt: due, loanClass: loan.dataClass, extendURL: loan.booking.extendURL,
            busy: busy, now: now, calendar: calendar, policy: policy
        )
    }

    /// The general form, for any due time.
    public static func check(
        bookingID: String, dueAt due: Date, loanClass: DataClass, extendURL: URL?, busy: [BusyBlock], now: Date,
        calendar: Calendar, policy: ReturnClashPolicy = .default
    ) -> ReturnClash? {
        let window = DateInterval(start: due.addingTimeInterval(-policy.returnDuration), end: due)
        let clashing = busy.filter { $0.interval.start < window.end && $0.interval.end > window.start }
        guard !clashing.isEmpty else { return nil }

        let searchStart = max(now, due.addingTimeInterval(-policy.lookback))
        let considered = busy.filter { $0.interval.end > searchStart && $0.interval.start < due }
        let slot = searchStart < due
            ? latestSlot(in: DateInterval(start: searchStart, end: due), busy: considered.map(\.interval), calendar: calendar, policy: policy)
            : nil
        return ReturnClash(
            bookingID: bookingID, dueAt: due, clashingIntervals: clashing.map(\.interval), proposedSlot: slot, extendURL: extendURL,
            dataClass: Taint.derive(.bookingReturnClash, from: [loanClass] + considered.map(\.dataClass) + clashing.map(\.dataClass))
        )
    }

    /// The latest `returnDuration` stretch inside `range` that is free and inside desk hours.
    static func latestSlot(in range: DateInterval, busy: [DateInterval], calendar: Calendar, policy: ReturnClashPolicy) -> DateInterval? {
        let free = subtract(busy, from: deskHours(in: range, calendar: calendar, policy: policy))
        for gap in free.reversed() where gap.duration >= policy.returnDuration {
            return DateInterval(start: gap.end.addingTimeInterval(-policy.returnDuration), end: gap.end)
        }
        return nil
    }

    /// Desk-hour intervals, one per local day, clipped to `range`, ascending.
    static func deskHours(in range: DateInterval, calendar: Calendar, policy: ReturnClashPolicy) -> [DateInterval] {
        var result: [DateInterval] = []
        var day = calendar.startOfDay(for: range.start)
        while day < range.end {
            guard let open = calendar.date(bySettingHour: policy.deskOpenHour, minute: 0, second: 0, of: day),
                  let next = calendar.date(byAdding: .day, value: 1, to: day)
            else { break }
            let close = policy.deskCloseHour >= 24
                ? next
                : calendar.date(bySettingHour: policy.deskCloseHour, minute: 0, second: 0, of: day) ?? next
            let start = max(open, range.start)
            let end = min(close, range.end)
            if start < end { result.append(DateInterval(start: start, end: end)) }
            day = next
        }
        return result
    }

    /// `intervals` minus `busy`, ascending.
    static func subtract(_ busy: [DateInterval], from intervals: [DateInterval]) -> [DateInterval] {
        let sorted = busy.sorted { $0.start < $1.start }
        var result: [DateInterval] = []
        for interval in intervals {
            var cursor = interval.start
            for block in sorted where block.end > cursor && block.start < interval.end {
                if block.start > cursor { result.append(DateInterval(start: cursor, end: block.start)) }
                cursor = max(cursor, block.end)
            }
            if cursor < interval.end { result.append(DateInterval(start: cursor, end: interval.end)) }
        }
        return result
    }
}
