import EagarCalendar
import EagarCore
import Foundation

/// Tunables for ``NudgePlanner``.
public struct NudgePlannerSettings: Sendable, Hashable {
    /// The weekly social-capacity budget (FR-PEOPLE-04). Default 3.
    public var weeklyBudget: Int
    /// The shortest free stretch worth proposing, in minutes.
    public var minimumSlotMinutes: Int
    /// Social hours: local hour from which slots are offered.
    public var dayStartHour: Int
    /// Social hours: local hour at which slots stop (24 means midnight).
    public var dayEndHour: Int
    /// The share of a cadence, counted back from its end, in which a nudge may be placed.
    /// With 30 days and 0.25, a nudge falls between day 22 and day 30 after the last contact.
    public var cadenceWindowFraction: Double

    public init(weeklyBudget: Int = 3, minimumSlotMinutes: Int = 60, dayStartHour: Int = 9, dayEndHour: Int = 22, cadenceWindowFraction: Double = 0.25) {
        self.weeklyBudget = max(0, weeklyBudget)
        self.minimumSlotMinutes = max(1, minimumSlotMinutes)
        self.dayStartHour = min(max(dayStartHour, 0), 23)
        self.dayEndHour = min(max(dayEndHour, self.dayStartHour + 1), 24)
        self.cadenceWindowFraction = min(max(cadenceWindowFraction, 0), 1)
    }
}

/// The span in which a person's next nudge may fall, before free slots are considered.
public struct CadenceWindow: Sendable, Hashable {
    public let interval: DateInterval
    public let reason: NudgeReason
}

/// Proposes keep-in-touch nudges for one week (FR-PEOPLE-04).
///
/// Rules:
/// - At most `weeklyBudget - alreadyCommitted` nudges.
/// - Each nudge sits wholly inside one free slot, clipped to social hours on one day and to the
///   part of the week after `now`; slots shorter than `minimumSlotMinutes` are never offered.
/// - At most one nudge per day, and never two in the same slot.
/// - A person's nudge falls inside their cadence window: for a person last seen at `L` with
///   cadence `C` days, between `L + C - ceil(C * fraction)` days and `L + C` days. Overdue people
///   and people with no known contact may be placed anywhere in the week.
/// - Weekday preferences and snoozes are respected.
/// - Order: overdue people first (most overdue relative to cadence first), then people due
///   soon (earliest due first), then people with no known contact (shuffled). Within those
///   rules the slot is chosen at random with the injected generator.
public enum NudgePlanner {
    public static func plan(
        people: [PersonSnapshot],
        inferences: [UUID: InteractionInference],
        freeSlots: [FreeSlot],
        week: DateInterval,
        now: Date,
        alreadyCommitted: Int = 0,
        settings: NudgePlannerSettings = NudgePlannerSettings(),
        calendar: Calendar,
        using generator: inout some RandomNumberGenerator
    ) -> [Nudge] {
        let budget = settings.weeklyBudget - max(0, alreadyCommitted)
        guard budget > 0, now < week.end else { return [] }
        let horizon = DateInterval(start: max(now, week.start), end: week.end)
        let pieces = socialPieces(freeSlots, horizon: horizon, settings: settings, calendar: calendar)
        guard !pieces.isEmpty else { return [] }

        let candidates = ordered(people.compactMap { person -> Candidate? in
            let inference = inferences[person.id]
            let last = inference?.effectiveLatest ?? person.lastInteractionAt
            guard let window = cadenceWindow(cadenceDays: person.cadenceDays, last: last, horizon: horizon, snoozedUntil: person.snoozedUntil, fraction: settings.cadenceWindowFraction, calendar: calendar)
            else { return nil }
            return Candidate(person: person, last: last, lastClass: inference?.effectiveClass ?? person.dataClass, window: window, now: now)
        }, using: &generator)

        var nudges: [Nudge] = []
        var usedDays = Set<Date>()
        let minimum = TimeInterval(settings.minimumSlotMinutes * 60)
        for candidate in candidates {
            guard nudges.count < budget else { break }
            let feasible = pieces.compactMap { piece -> Piece? in
                guard !usedDays.contains(piece.day),
                      candidate.person.preferredWeekdays.isEmpty
                        || candidate.person.preferredWeekdays.contains(calendar.component(.weekday, from: piece.interval.start)),
                      let clipped = piece.interval.intersection(with: candidate.window.interval),
                      clipped.duration >= minimum
                else { return nil }
                return Piece(interval: clipped, day: piece.day, dataClass: piece.dataClass)
            }
            guard let chosen = feasible.randomElement(using: &generator) else { continue }
            usedDays.insert(chosen.day)
            nudges.append(Nudge(
                personID: candidate.person.id,
                displayName: candidate.person.displayName,
                slot: chosen.interval,
                reason: candidate.window.reason,
                daysSince: candidate.last.map { max(0, calendar.dateComponents([.day], from: $0, to: now).day ?? 0) },
                dataClass: Taint.derive(.keepInTouchNudge, from: [candidate.person.dataClass, chosen.dataClass, candidate.lastClass])
            ))
        }
        return nudges
    }

    /// The span in which the next nudge for this person may fall within `horizon`, or nil.
    public static func cadenceWindow(
        cadenceDays: Int, last: Date?, horizon: DateInterval, snoozedUntil: Date?, fraction: Double, calendar: Calendar
    ) -> CadenceWindow? {
        var start = horizon.start
        var end = horizon.end
        let reason: NudgeReason
        if let last {
            guard let due = calendar.date(byAdding: .day, value: cadenceDays, to: last) else { return nil }
            if due <= horizon.start {
                reason = .overdue
            } else {
                let lead = max(0, Int((Double(cadenceDays) * fraction).rounded(.up)))
                let earliestDays = max(min(1, cadenceDays), cadenceDays - lead)
                guard let earliest = calendar.date(byAdding: .day, value: earliestDays, to: last) else { return nil }
                reason = .dueSoon
                start = max(start, earliest)
                end = min(end, due)
            }
        } else {
            reason = .noContactYet
        }
        if let snoozedUntil { start = max(start, snoozedUntil) }
        guard start < end else { return nil }
        return CadenceWindow(interval: DateInterval(start: start, end: end), reason: reason)
    }

    // MARK: Internals

    struct Piece {
        let interval: DateInterval
        /// Start of the local day the piece lies in.
        let day: Date
        let dataClass: DataClass
    }

    struct Candidate {
        let person: PersonSnapshot
        let last: Date?
        let lastClass: DataClass
        let window: CadenceWindow
        let now: Date

        /// Days since last contact as a share of the cadence; higher is more overdue.
        var overdueRatio: Double {
            guard let last else { return 0 }
            return now.timeIntervalSince(last) / (Double(person.cadenceDays) * 86_400)
        }
    }

    /// Free slots split into per-day pieces inside social hours and `horizon`, ascending.
    static func socialPieces(_ slots: [FreeSlot], horizon: DateInterval, settings: NudgePlannerSettings, calendar: Calendar) -> [Piece] {
        let minimum = TimeInterval(settings.minimumSlotMinutes * 60)
        var pieces: [Piece] = []
        for slot in slots.sorted(by: { $0.interval.start < $1.interval.start }) {
            guard let clipped = slot.interval.intersection(with: horizon), clipped.duration > 0 else { continue }
            var day = calendar.startOfDay(for: clipped.start)
            while day < clipped.end {
                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                let open = calendar.date(bySettingHour: settings.dayStartHour, minute: 0, second: 0, of: day) ?? day
                let close = settings.dayEndHour >= 24 ? next : (calendar.date(bySettingHour: settings.dayEndHour, minute: 0, second: 0, of: day) ?? next)
                if open < close, let piece = clipped.intersection(with: DateInterval(start: open, end: close)), piece.duration >= minimum {
                    pieces.append(Piece(interval: piece, day: day, dataClass: slot.dataClass))
                }
                day = next
            }
        }
        return pieces
    }

    static func ordered(_ candidates: [Candidate], using generator: inout some RandomNumberGenerator) -> [Candidate] {
        let byID = candidates.sorted { $0.person.id.uuidString < $1.person.id.uuidString }
        let overdue = byID.filter { $0.window.reason == .overdue }.sorted { $0.overdueRatio > $1.overdueRatio }
        let dueSoon = byID.filter { $0.window.reason == .dueSoon }.sorted { $0.window.interval.end < $1.window.interval.end }
        let fresh = byID.filter { $0.window.reason == .noContactYet }.shuffled(using: &generator)
        return overdue + dueSoon + fresh
    }
}

/// How much of the weekly budget is already spent.
public enum NudgeBudget {
    /// Contact logs that fall inside `week`. Add catch-ups Mark planned from nudges for this
    /// week (started or not) to get the planner's `alreadyCommitted`.
    public static func loggedContacts(_ logs: [ContactLogSnapshot], in week: DateInterval) -> Int {
        logs.filter { $0.occurredAt >= week.start && $0.occurredAt < week.end }.count
    }

    /// The local week (per `calendar.firstWeekday`) containing `date`.
    public static func week(containing date: Date, calendar: Calendar) -> DateInterval? {
        calendar.dateInterval(of: .weekOfYear, for: date)
    }
}
