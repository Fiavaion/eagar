import EagarCalendar
import EagarCore
import Foundation

/// Where an interaction signal came from.
public enum InteractionSignalKind: String, Sendable, Hashable, CaseIterable {
    /// A past calendar event with the person as an attendee.
    case calendarEvent
    /// Mail to or from the person.
    case mail
    /// A manual "we talked" log.
    case manualLog
}

/// Mail exchanged with someone, reduced to what inference needs (FR-PEOPLE-03). Mail arrives
/// in M3; the mail package will produce these from message headers, never from bodies.
///
/// `dataClass` is the lane's class: personal-lane mail is `personal`, work-lane (NCAD) mail
/// is `college`.
public struct MailContactSignal: Sendable, Hashable, Classified {
    /// Counterpart addresses (sender, or recipients for sent mail). Normalised on init.
    public let addresses: [String]
    public let date: Date
    public let dataClass: DataClass
    public let sourceID: SourceID?

    public init(addresses: [String], date: Date, dataClass: DataClass, sourceID: SourceID? = nil) {
        self.addresses = normalisedEmails(addresses)
        self.date = date
        self.dataClass = dataClass
        self.sourceID = sourceID
    }
}

/// Something that suggests Mark was in touch with a person at `date`.
public struct InteractionSignal: Sendable, Hashable, Classified {
    public let date: Date
    public let kind: InteractionSignalKind
    public let dataClass: DataClass
    public var sourceID: SourceID? { nil }

    public init(date: Date, kind: InteractionSignalKind, dataClass: DataClass) {
        self.date = date
        self.kind = kind
        self.dataClass = dataClass
    }
}

/// The inferred last interaction with one person (FR-PEOPLE-03).
///
/// Two answers are kept apart:
/// - `personalLatest` uses personal signals only. It is the only value that may be written to
///   ``Person/lastInteractionAt`` and so reach CloudKit.
/// - `effectiveLatest` also uses college signals when the person's work-signal opt-in is on.
///   Its class, `effectiveClass`, is the taint of every counted signal, so it is `college` as
///   soon as one college signal is counted, even when that signal is not the latest one (a
///   personal date that won only because no college date beat it still reveals something
///   about the college data). Planners use it on the device; it is never persisted.
public struct InteractionInference: Sendable, Hashable {
    public let personID: UUID
    public let personalLatest: Date?
    public let effectiveLatest: Date?
    public let effectiveClass: DataClass
    /// How many signals counted (after the opt-in filter).
    public let countedSignals: Int
    /// How many college signals were ignored because the opt-in is off.
    public let ignoredCollegeSignals: Int

    public init(personID: UUID, personalLatest: Date?, effectiveLatest: Date?, effectiveClass: DataClass, countedSignals: Int, ignoredCollegeSignals: Int) {
        self.personID = personID
        self.personalLatest = personalLatest
        self.effectiveLatest = effectiveLatest
        self.effectiveClass = effectiveClass
        self.countedSignals = countedSignals
        self.ignoredCollegeSignals = ignoredCollegeSignals
    }
}

/// Pure last-interaction inference (FR-PEOPLE-03, BD-26). No I/O, no model calls: it runs over
/// college data, so it stays deterministic and on-device.
public enum InteractionInferrer {
    /// Signals for `person` from the given sources. Events count once they have ended by `now`;
    /// future mail or logs (clock skew) are ignored.
    public static func signals(
        for person: PersonSnapshot,
        events: [ClassifiedEvent],
        mail: [MailContactSignal],
        logs: [ContactLogSnapshot],
        now: Date
    ) -> [InteractionSignal] {
        let addresses = Set(person.emailAddresses)
        var result: [InteractionSignal] = []
        if !addresses.isEmpty {
            for item in events where item.event.end <= now {
                if !addresses.isDisjoint(with: item.event.attendeeEmails.map { $0.lowercased() }) {
                    result.append(InteractionSignal(date: item.event.end, kind: .calendarEvent, dataClass: item.dataClass))
                }
            }
            for item in mail where item.date <= now && !addresses.isDisjoint(with: item.addresses) {
                result.append(InteractionSignal(date: item.date, kind: .mail, dataClass: item.dataClass))
            }
        }
        for log in logs where log.personID == person.id && log.occurredAt <= now {
            result.append(InteractionSignal(date: log.occurredAt, kind: .manualLog, dataClass: log.dataClass))
        }
        return result
    }

    /// Combines `signals` with the person's stored personal date.
    ///
    /// College signals count only when `person.workSignalsOptIn` is on. The effective class is
    /// `Taint.derive(.keepInTouchInteraction, ...)` over the person's class and every counted
    /// signal.
    public static func infer(person: PersonSnapshot, signals: [InteractionSignal]) -> InteractionInference {
        let counted = signals.filter { $0.dataClass != .college || person.workSignalsOptIn }
        let ignored = signals.count - counted.count
        let personalDates = counted.filter { $0.dataClass != .college }.map(\.date) + [person.lastInteractionAt].compactMap { $0 }
        let allDates = counted.map(\.date) + [person.lastInteractionAt].compactMap { $0 }
        return InteractionInference(
            personID: person.id,
            personalLatest: personalDates.max(),
            effectiveLatest: allDates.max(),
            effectiveClass: Taint.derive(.keepInTouchInteraction, from: [person.dataClass] + counted.map(\.dataClass)),
            countedSignals: counted.count,
            ignoredCollegeSignals: ignored
        )
    }

    /// `signals(for:...)` then `infer(person:signals:)`, for every person.
    public static func infer(
        people: [PersonSnapshot],
        events: [ClassifiedEvent],
        mail: [MailContactSignal],
        logs: [ContactLogSnapshot],
        now: Date
    ) -> [UUID: InteractionInference] {
        Dictionary(uniqueKeysWithValues: people.map { person in
            (person.id, infer(person: person, signals: signals(for: person, events: events, mail: mail, logs: logs, now: now)))
        })
    }
}

extension Person {
    /// Writes the personal part of `inference` to `lastInteractionAt`. The effective
    /// (possibly college) date is never stored here, because this record syncs to CloudKit.
    public func apply(_ inference: InteractionInference) {
        guard inference.personID == personUUID, let date = inference.personalLatest else { return }
        notePersonalInteraction(at: date)
    }
}
