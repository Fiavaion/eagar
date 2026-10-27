import EagarCalendar
import EagarCore
import Foundation

/// What Mark can do with a nudge (FR-PEOPLE-05).
public enum NudgeAction: Sendable, Hashable {
    /// Put a catch-up in the calendar in the nudge's slot.
    case plan
    /// Record that they were in touch, at the given time.
    case logContact(at: Date, note: String = "")
    /// Hide this person's nudges for this many days.
    case snooze(days: Int)
    /// Set a new cadence in days.
    case changeCadence(days: Int)
}

/// A manual contact log to insert, as a value.
public struct ContactLogDraft: Sendable, Hashable {
    public let personID: UUID
    public let occurredAt: Date
    public let kind: ContactLogKind
    public let note: String

    public init(personID: UUID, occurredAt: Date, kind: ContactLogKind = .manual, note: String = "") {
        self.personID = personID
        self.occurredAt = occurredAt
        self.kind = kind
        self.note = note
    }

    /// The model to insert into PersonalStore.
    public func makeLog(createdAt: Date) -> ContactLog {
        ContactLog(personUUID: personID, occurredAt: occurredAt, kind: kind, note: note, createdAt: createdAt)
    }
}

/// The result of a nudge action: values only, applied by the app.
public struct NudgeEffect: Sendable, Hashable {
    public var personID: UUID
    /// An event to write with the calendar write guard (FR-CAL-04); `eventClass` is its class.
    public var eventDraft: EventDraft?
    /// The class of `eventDraft`'s timing and content: the nudge's class.
    public var eventClass: DataClass?
    public var contactLog: ContactLogDraft?
    public var snoozedUntil: Date?
    public var cadenceDays: Int?
    /// Whether this action spends one unit of the weekly social budget.
    public var consumesBudget: Bool

    public init(personID: UUID, eventDraft: EventDraft? = nil, eventClass: DataClass? = nil, contactLog: ContactLogDraft? = nil, snoozedUntil: Date? = nil, cadenceDays: Int? = nil, consumesBudget: Bool = false) {
        self.personID = personID
        self.eventDraft = eventDraft
        self.eventClass = eventClass
        self.contactLog = contactLog
        self.snoozedUntil = snoozedUntil
        self.cadenceDays = cadenceDays
        self.consumesBudget = consumesBudget
    }
}

/// Pure handlers for ``NudgeAction`` (FR-PEOPLE-05).
public enum NudgeActions {
    /// The default length of a planned catch-up.
    public static let defaultEventMinutes = 90

    public static func effect(
        of action: NudgeAction, for nudge: Nudge, now: Date, calendar: Calendar,
        eventMinutes: Int = defaultEventMinutes
    ) -> NudgeEffect {
        switch action {
        case .plan:
            let end = min(nudge.slot.end, nudge.slot.start.addingTimeInterval(TimeInterval(max(15, eventMinutes) * 60)))
            let title = String(localized: "Catch up with \(nudge.displayName)", bundle: .module, comment: "Calendar event title for a planned keep-in-touch catch-up")
            return NudgeEffect(
                personID: nudge.personID,
                eventDraft: EventDraft(title: title, start: nudge.slot.start, end: end),
                eventClass: nudge.dataClass,
                consumesBudget: true
            )
        case let .logContact(at, note):
            return NudgeEffect(
                personID: nudge.personID,
                contactLog: ContactLogDraft(personID: nudge.personID, occurredAt: min(at, now), kind: .nudge, note: note),
                consumesBudget: true
            )
        case let .snooze(days):
            let start = calendar.startOfDay(for: now)
            let until = calendar.date(byAdding: .day, value: max(1, days), to: start) ?? now.addingTimeInterval(TimeInterval(max(1, days)) * 86_400)
            return NudgeEffect(personID: nudge.personID, snoozedUntil: until)
        case let .changeCadence(days):
            return NudgeEffect(personID: nudge.personID, cadenceDays: Person.clampedCadence(days))
        }
    }
}

extension Person {
    /// Applies the person-level parts of `effect`. The contact log and event are the app's to
    /// insert and write; a logged contact also moves `lastInteractionAt`, since it is personal.
    public func apply(_ effect: NudgeEffect) {
        guard effect.personID == personUUID else { return }
        if let until = effect.snoozedUntil { snoozedUntil = until }
        if let days = effect.cadenceDays { setCadence(days: days) }
        if let log = effect.contactLog {
            notePersonalInteraction(at: log.occurredAt)
            snoozedUntil = nil
        }
    }
}
