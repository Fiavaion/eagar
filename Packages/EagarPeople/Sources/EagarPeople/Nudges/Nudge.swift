import EagarCore
import Foundation

/// Why a person is being nudged.
public enum NudgeReason: String, Sendable, Hashable, CaseIterable {
    /// The cadence has run out.
    case overdue
    /// The cadence runs out soon; the nudge falls inside its randomisation window.
    case dueSoon
    /// No interaction is known yet.
    case noContactYet
}

/// A proposed keep-in-touch catch-up in a free slot (FR-PEOPLE-04, 05).
///
/// Carries enough for phrasing like "Thursday evening is free; Aoife: 7 weeks" (see
/// ``NudgePhrasing``). `dataClass` is the taint of the person, the free slot and the inferred
/// interaction, so a nudge placed after a college event, or timed from a college signal, is
/// `college`: show it on the device only, and keep notifications for it content-free.
public struct Nudge: Sendable, Hashable, Identifiable {
    public let id: String
    public let personID: UUID
    public let displayName: String
    /// The free time proposed, inside one day's social hours.
    public let slot: DateInterval
    public let reason: NudgeReason
    /// Whole days since the last known interaction, as of planning; nil when none is known.
    public let daysSince: Int?
    public let dataClass: DataClass

    public init(personID: UUID, displayName: String, slot: DateInterval, reason: NudgeReason, daysSince: Int?, dataClass: DataClass) {
        id = "nudge.\(personID.uuidString).\(Int(slot.start.timeIntervalSince1970))"
        self.personID = personID
        self.displayName = displayName
        self.slot = slot
        self.reason = reason
        self.daysSince = daysSince
        self.dataClass = dataClass
    }

    /// Whole weeks since the last interaction; nil when none is known.
    public var weeksSince: Int? { daysSince.map { $0 / 7 } }
    public var isOverdue: Bool { reason == .overdue }
}
