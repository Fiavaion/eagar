import EagarCore
import Foundation

/// A birthday reminder the planner wants scheduled as a local notification (FR-PEOPLE-06).
public struct PlannedBirthdayNotification: Sendable, Hashable, Identifiable {
    public let id: String
    public let personID: UUID
    public let fireDate: Date
    public let title: String
    public let body: String
    public let categoryIdentifier: String
    public let threadIdentifier: String
}

/// Pure planner from people to birthday notifications. No server: birthdays are local
/// notifications scheduled at sync time (RESEARCH "notify" section).
///
/// One notification per person, for the next birthday, at `fireHour` local time on the day.
/// A 29 February birthday falls on 28 February in common years. Without a birth year the text
/// leaves the age out.
public enum BirthdayNotificationPlan {
    public static let identifierPrefix = "birthday."
    public static let categoryIdentifier = "birthday"
    public static let defaultFireHour = 9

    public static func identifier(personID: UUID, year: Int) -> String {
        "\(identifierPrefix)\(personID.uuidString).\(year)"
    }

    public static func plan(
        _ people: [PersonSnapshot], now: Date, calendar: Calendar = .current, fireHour: Int = defaultFireHour
    ) -> [PlannedBirthdayNotification] {
        people.compactMap { plan(for: $0, now: now, calendar: calendar, fireHour: fireHour) }
    }

    static func plan(for person: PersonSnapshot, now: Date, calendar: Calendar, fireHour: Int) -> PlannedBirthdayNotification? {
        // People are personal by construction; a record reading as college (unknown class) is
        // skipped rather than given a notification with a name in it (BD-04).
        guard person.dataClass != .college, let birthday = person.birthday,
              let next = nextOccurrence(of: birthday, after: now, calendar: calendar, fireHour: fireHour)
        else { return nil }
        let name = person.displayName
        let title = String(localized: "\(name)’s birthday", bundle: .module, comment: "Birthday notification title; the argument is a name")
        let body: String
        if let born = birthday.year, next.year - born > 0 {
            let age = next.year - born
            body = String(localized: "Turns \(age) today", bundle: .module, comment: "Birthday notification body with age")
        } else {
            body = String(localized: "Birthday today", bundle: .module, comment: "Birthday notification body without age")
        }
        return PlannedBirthdayNotification(
            id: identifier(personID: person.id, year: next.year),
            personID: person.id,
            fireDate: next.date,
            title: title,
            body: body,
            categoryIdentifier: categoryIdentifier,
            threadIdentifier: "birthday.\(person.id.uuidString)"
        )
    }

    /// The first birthday reminder strictly after `now`, and the year it falls in.
    public static func nextOccurrence(of birthday: Birthday, after now: Date, calendar: Calendar, fireHour: Int = defaultFireHour) -> (date: Date, year: Int)? {
        let thisYear = calendar.component(.year, from: now)
        for year in thisYear...(thisYear + 1) {
            guard let date = occurrence(of: birthday, in: year, calendar: calendar, fireHour: fireHour) else { continue }
            if date > now { return (date, year) }
        }
        return nil
    }

    /// The reminder time in `year`; 29 February becomes 28 February in common years.
    static func occurrence(of birthday: Birthday, in year: Int, calendar: Calendar, fireHour: Int) -> Date? {
        var day = birthday.day
        if birthday.isLeapDay && !isLeapYear(year, calendar: calendar) { day = 28 }
        var components = DateComponents(year: year, month: birthday.month, day: day, hour: fireHour)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        return calendar.date(from: components)
    }

    static func isLeapYear(_ year: Int, calendar: Calendar) -> Bool {
        guard let feb = calendar.date(from: DateComponents(year: year, month: 2, day: 1)) else { return false }
        return calendar.range(of: .day, in: .month, for: feb)?.count == 29
    }
}
