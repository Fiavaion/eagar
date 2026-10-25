import EagarCore
import Foundation

/// A stretch of merged busy time inside an availability window (FR-CAL-03).
///
/// Overlapping or touching blocking events merge into one block.
/// `dataClass` is `Taint.derive(.calendarAvailability, from:)` over the contributing events' classes,
/// so a block that merges a college event with a personal one is college (BD-03).
public struct BusyBlock: Sendable, Hashable {
    /// The busy time, clipped to the requested window.
    public let interval: DateInterval
    /// The taint of every contributing event.
    public let dataClass: DataClass
    /// Identifiers of the contributing events, ordered by start, without duplicates.
    public let eventIDs: [String]

    public init(interval: DateInterval, dataClass: DataClass, eventIDs: [String]) {
        self.interval = interval
        self.dataClass = dataClass
        self.eventIDs = eventIDs
    }
}

/// A free stretch between busy blocks, inside an availability window (FR-CAL-03).
///
/// `dataClass` is the class of the busy block that ends where the slot starts, or
/// `.publicContent` when the slot starts at the window start with nothing before it.
/// Knowing where a slot starts reveals when that block ended, so the slot inherits its class.
public struct FreeSlot: Sendable, Hashable {
    public let interval: DateInterval
    public let dataClass: DataClass

    public init(interval: DateInterval, dataClass: DataClass) {
        self.interval = interval
        self.dataClass = dataClass
    }
}

/// Two blocking events whose times overlap inside the window (FR-CAL-03).
///
/// Carries identifiers only, never titles or locations. Touching events (one ends as the
/// other starts) do not conflict. `dataClass` is `Taint.derive(.calendarAvailability, from:)`
/// over both events' classes.
public struct Conflict: Sendable, Hashable {
    /// The two event identifiers, in ascending order.
    public let eventIDs: [String]
    /// The overlapping time, clipped to the window.
    public let overlap: DateInterval
    public let dataClass: DataClass

    public init(eventIDs: [String], overlap: DateInterval, dataClass: DataClass) {
        self.eventIDs = eventIDs
        self.overlap = overlap
        self.dataClass = dataClass
    }
}

/// A natural break at which the Brief may be delivered (BD-21, FR-CAL-03).
public struct Breakpoint: Sendable, Hashable {
    /// Why this instant is a break.
    public enum Kind: String, Sendable, Hashable, CaseIterable {
        /// A merged busy block ends.
        case eventEnd
        /// A free gap of at least the minimum length starts, with no busy block ending there.
        case gapStart
    }

    public let date: Date
    public let kind: Kind
    /// For `.eventEnd`, the class of the block that ends. For `.gapStart`, the class of the
    /// block that ends at the gap's start, or `.publicContent` when there is none.
    public let dataClass: DataClass

    public init(date: Date, kind: Kind, dataClass: DataClass) {
        self.date = date
        self.kind = kind
        self.dataClass = dataClass
    }
}
