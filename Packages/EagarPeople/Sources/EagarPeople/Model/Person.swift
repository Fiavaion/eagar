import EagarCore
import Foundation
import SwiftData

/// The cadence a newly added person starts with, in days.
public let defaultCadenceDays = 30
/// The shortest cadence Eagar accepts, in days.
public let minimumCadenceDays = 1
/// The longest cadence Eagar accepts, in days (two years).
public let maximumCadenceDays = 730

/// Someone Mark wants to keep in touch with (FR-PEOPLE-01, 02, BD-26). Always `personal`.
///
/// CloudKit-compatible: every attribute defaulted or optional, no unique constraints, no
/// relationships. Logical uniqueness (one person per contact) is enforced by ``PersonUpsert``.
///
/// `lastInteractionAt` holds only personal-derived evidence. Interactions inferred from
/// college signals (work-lane mail, college calendars) are never written here, because this
/// record syncs through CloudKit; see ``InteractionInference``.
@Model
public final class Person: Classified {
    public var personUUID: UUID = UUID()
    /// `CNContact.identifier` of the contact Mark picked, if any.
    public var contactIdentifier: String?
    public var displayName: String = ""
    /// Lower-cased addresses used to match calendar attendees and personal-lane mail.
    public var emailAddresses: [String] = []
    public var birthdayMonth: Int?
    public var birthdayDay: Int?
    public var birthdayYear: Int?
    public var cadenceDays: Int = defaultCadenceDays
    /// `Calendar` weekday numbers (1 = Sunday ... 7 = Saturday). Empty means any day.
    public var preferredWeekdays: [Int] = []
    /// Mark's own notes about the relationship. Synced only in CloudKit `encryptedValues`.
    public var relationshipNotes: String = ""
    /// The latest personal-class interaction Eagar knows of.
    public var lastInteractionAt: Date?
    public var snoozedUntil: Date?
    /// Whether work-lane and college-calendar signals count for this person (FR-PEOPLE-03).
    public var workSignalsOptIn: Bool = false
    /// Unknown or missing values read as college (fail closed); new people are personal.
    public var dataClassRaw: String = DataClass.college.rawValue
    public var createdAt: Date = Date.distantPast

    public init(
        personUUID: UUID = UUID(),
        contactIdentifier: String? = nil,
        displayName: String,
        emailAddresses: [String] = [],
        birthday: Birthday? = nil,
        cadenceDays: Int = defaultCadenceDays,
        preferredWeekdays: [Int] = [],
        dataClass: DataClass = .personal,
        createdAt: Date
    ) {
        self.personUUID = personUUID
        self.contactIdentifier = contactIdentifier
        self.displayName = displayName
        self.emailAddresses = normalisedEmails(emailAddresses)
        self.cadenceDays = Self.clampedCadence(cadenceDays)
        self.preferredWeekdays = Self.cleanWeekdays(preferredWeekdays)
        dataClassRaw = dataClass.rawValue
        self.createdAt = createdAt
        self.birthday = birthday
    }

    public var dataClass: DataClass { DataClass(rawValue: dataClassRaw) ?? .college }
    /// People are added by Mark, so they have no source.
    public var sourceID: SourceID? { nil }

    public var birthday: Birthday? {
        get { birthdayMonth.flatMap { m in birthdayDay.flatMap { d in Birthday(month: m, day: d, year: birthdayYear) } } }
        set {
            birthdayMonth = newValue?.month
            birthdayDay = newValue?.day
            birthdayYear = newValue?.year
        }
    }

    public func setCadence(days: Int) { cadenceDays = Self.clampedCadence(days) }
    public func setPreferredWeekdays(_ weekdays: [Int]) { preferredWeekdays = Self.cleanWeekdays(weekdays) }
    public func setEmailAddresses(_ addresses: [String]) { emailAddresses = normalisedEmails(addresses) }

    /// Records personal evidence of contact. Older dates never move the value backwards.
    public func notePersonalInteraction(at date: Date) {
        if lastInteractionAt.map({ date > $0 }) ?? true { lastInteractionAt = date }
    }

    /// A value copy for planners and inference, which never touch the model.
    public var snapshot: PersonSnapshot {
        PersonSnapshot(
            id: personUUID, displayName: displayName, emailAddresses: emailAddresses, birthday: birthday,
            cadenceDays: cadenceDays, preferredWeekdays: Set(preferredWeekdays), lastInteractionAt: lastInteractionAt,
            snoozedUntil: snoozedUntil, workSignalsOptIn: workSignalsOptIn, dataClass: dataClass, createdAt: createdAt
        )
    }

    static func clampedCadence(_ days: Int) -> Int { min(max(days, minimumCadenceDays), maximumCadenceDays) }

    static func cleanWeekdays(_ weekdays: [Int]) -> [Int] { Set(weekdays.filter { (1...7).contains($0) }).sorted() }
}

/// A `Sendable` value copy of a ``Person``.
public struct PersonSnapshot: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let displayName: String
    public let emailAddresses: [String]
    public let birthday: Birthday?
    public let cadenceDays: Int
    /// `Calendar` weekday numbers; empty means any day.
    public let preferredWeekdays: Set<Int>
    public let lastInteractionAt: Date?
    public let snoozedUntil: Date?
    public let workSignalsOptIn: Bool
    public let dataClass: DataClass
    public let createdAt: Date

    public init(
        id: UUID = UUID(), displayName: String, emailAddresses: [String] = [], birthday: Birthday? = nil,
        cadenceDays: Int = defaultCadenceDays, preferredWeekdays: Set<Int> = [], lastInteractionAt: Date? = nil,
        snoozedUntil: Date? = nil, workSignalsOptIn: Bool = false, dataClass: DataClass = .personal,
        createdAt: Date = .distantPast
    ) {
        self.id = id
        self.displayName = displayName
        self.emailAddresses = normalisedEmails(emailAddresses)
        self.birthday = birthday
        self.cadenceDays = Person.clampedCadence(cadenceDays)
        self.preferredWeekdays = preferredWeekdays.filter { (1...7).contains($0) }
        self.lastInteractionAt = lastInteractionAt
        self.snoozedUntil = snoozedUntil
        self.workSignalsOptIn = workSignalsOptIn
        self.dataClass = dataClass
        self.createdAt = createdAt
    }
}
