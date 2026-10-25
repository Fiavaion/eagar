import EagarCore
import Foundation

/// Deterministic free/busy, conflict and breakpoint computation (FR-CAL-03, BD-21).
///
/// Pure functions with no AI, no EventKit and no I/O, so they run for every calendar,
/// college included. Every result is clipped to the requested window, treated as half-open
/// (`[start, end)`): a breakpoint lies at or after `window.start` and strictly before `window.end`.
///
/// Rules:
/// - Timed events block time when their availability is `.busy`, `.tentative` or `.unavailable`;
///   `.free` and `.notSupported` do not.
/// - All-day events block whole local days, computed with the injected `Calendar`, and only when
///   their availability is `.busy` or `.unavailable` (EventKit reports holidays and birthdays as free).
///   A local day in a DST transition is 23 or 25 hours long.
/// - Events whose end is not after their start are ignored.
///
/// Taint (BD-03):
/// - A ``BusyBlock``, its `.eventEnd` ``Breakpoint`` and a ``Conflict`` carry
///   `Taint.derive(.calendarAvailability, from:)` over the contributing events' classes.
/// - A ``FreeSlot`` and a `.gapStart` ``Breakpoint`` carry the class of the busy block ending where
///   they start, or `.publicContent` when no block ends there.
public enum AvailabilityEngine {
    /// The shortest free gap that counts as a breakpoint (BD-21): 15 minutes.
    public static let defaultMinimumGap: TimeInterval = 15 * 60

    /// Merged busy time inside `window`, ascending. Overlapping or touching blocks merge.
    public static func busyBlocks(for events: [ClassifiedEvent], in window: DateInterval, calendar: Calendar) -> [BusyBlock] {
        var blocks: [BusyBlock] = []
        var start = Date.distantPast
        var end = Date.distantPast
        var ids: [String] = []
        var classes: [DataClass] = []

        func flush() {
            guard !ids.isEmpty else { return }
            blocks.append(BusyBlock(
                interval: DateInterval(start: start, end: end),
                dataClass: Taint.derive(.calendarAvailability, from: classes),
                eventIDs: ids
            ))
        }

        for item in blockingIntervals(for: events, in: window, calendar: calendar) {
            if ids.isEmpty || item.interval.start > end {
                flush()
                start = item.interval.start
                end = item.interval.end
                ids = [item.id]
                classes = [item.dataClass]
            } else {
                end = max(end, item.interval.end)
                if !ids.contains(item.id) { ids.append(item.id) }
                classes.append(item.dataClass)
            }
        }
        flush()
        return blocks
    }

    /// Free time inside `window` that lasts at least `minimum` seconds, ascending.
    public static func freeSlots(for events: [ClassifiedEvent], in window: DateInterval, calendar: Calendar, minimum: TimeInterval = 0) -> [FreeSlot] {
        gaps(between: busyBlocks(for: events, in: window, calendar: calendar), in: window)
            .filter { $0.interval.duration >= minimum }
    }

    /// Every pair of blocking events whose times overlap inside `window`, ordered by overlap start.
    public static func conflicts(for events: [ClassifiedEvent], in window: DateInterval, calendar: Calendar) -> [Conflict] {
        let items = blockingIntervals(for: events, in: window, calendar: calendar)
        var result: [Conflict] = []
        for (index, first) in items.enumerated() {
            for second in items[(index + 1)...] {
                // Sorted by start: once a later item starts at or after `first` ends, none overlap.
                guard second.interval.start < first.interval.end else { break }
                guard second.id != first.id else { continue }
                let overlap = DateInterval(
                    start: second.interval.start,
                    end: min(first.interval.end, second.interval.end)
                )
                result.append(Conflict(
                    eventIDs: [first.id, second.id].sorted(),
                    overlap: overlap,
                    dataClass: Taint.derive(.calendarAvailability, from: [first.dataClass, second.dataClass])
                ))
            }
        }
        return result.sorted {
            ($0.overlap.start, $0.eventIDs[0], $0.eventIDs[1]) < ($1.overlap.start, $1.eventIDs[0], $1.eventIDs[1])
        }
    }

    /// Delivery breakpoints inside `window`, ascending (BD-21).
    ///
    /// An `.eventEnd` at the end of each merged busy block that ends before `window.end`, and a
    /// `.gapStart` at the start of each free gap of at least `minimumGap` seconds. When a block's end
    /// also starts such a gap, only the `.eventEnd` is emitted, so in practice a `.gapStart` appears
    /// only at `window.start`.
    public static func breakpoints(for events: [ClassifiedEvent], in window: DateInterval, calendar: Calendar, minimumGap: TimeInterval = defaultMinimumGap) -> [Breakpoint] {
        let blocks = busyBlocks(for: events, in: window, calendar: calendar)
        var result: [Breakpoint] = blocks
            .filter { $0.interval.end < window.end }
            .map { Breakpoint(date: $0.interval.end, kind: .eventEnd, dataClass: $0.dataClass) }
        let ends = Set(result.map(\.date))
        for gap in gaps(between: blocks, in: window) where gap.interval.duration >= minimumGap && !ends.contains(gap.interval.start) {
            result.append(Breakpoint(date: gap.interval.start, kind: .gapStart, dataClass: gap.dataClass))
        }
        return result.sorted { $0.date < $1.date }
    }

    // MARK: - Internals

    /// One blocking event's time, clipped to the window.
    private struct BlockingInterval {
        let id: String
        let interval: DateInterval
        let dataClass: DataClass
    }

    /// Blocking events clipped to `window`, sorted by start, end, then identifier.
    private static func blockingIntervals(for events: [ClassifiedEvent], in window: DateInterval, calendar: Calendar) -> [BlockingInterval] {
        events.compactMap { item -> BlockingInterval? in
            guard let raw = blockingRange(of: item.event, calendar: calendar) else { return nil }
            let start = max(raw.start, window.start)
            let end = min(raw.end, window.end)
            guard end > start else { return nil }
            return BlockingInterval(id: item.id, interval: DateInterval(start: start, end: end), dataClass: item.dataClass)
        }
        .sorted {
            ($0.interval.start, $0.interval.end, $0.id) < ($1.interval.start, $1.interval.end, $1.id)
        }
    }

    /// The unclipped time an event blocks, or `nil` when it blocks none.
    private static func blockingRange(of event: CalendarEvent, calendar: Calendar) -> (start: Date, end: Date)? {
        guard event.end > event.start else { return nil }
        guard event.isAllDay else {
            switch event.availability {
            case .busy, .tentative, .unavailable: return (event.start, event.end)
            case .free, .notSupported: return nil
            }
        }
        switch event.availability {
        case .busy, .unavailable: break
        case .tentative, .free, .notSupported: return nil
        }
        // Whole local days: from the start of the first day to the start of the day after the last.
        // An end exactly at local midnight is exclusive; EventKit's 23:59:59 end rounds up.
        let start = calendar.startOfDay(for: event.start)
        let endDay = calendar.startOfDay(for: event.end)
        if endDay == event.end { return (start, endDay) }
        guard let end = calendar.date(byAdding: .day, value: 1, to: endDay) else { return nil }
        return (start, end)
    }

    /// The free gaps between `blocks` inside `window`, each classed by the block ending at its start.
    private static func gaps(between blocks: [BusyBlock], in window: DateInterval) -> [FreeSlot] {
        var result: [FreeSlot] = []
        var cursor = window.start
        var previous: DataClass = .publicContent
        for block in blocks {
            if block.interval.start > cursor {
                result.append(FreeSlot(interval: DateInterval(start: cursor, end: block.interval.start), dataClass: previous))
            }
            cursor = block.interval.end
            previous = block.dataClass
        }
        if window.end > cursor {
            result.append(FreeSlot(interval: DateInterval(start: cursor, end: window.end), dataClass: previous))
        }
        return result
    }
}
