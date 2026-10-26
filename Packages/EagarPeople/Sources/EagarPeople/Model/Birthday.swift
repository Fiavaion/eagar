import Foundation

/// A birthday as Contacts gives it: month and day, with the year when known (FR-PEOPLE-06).
public struct Birthday: Sendable, Hashable, Codable {
    /// 1...12.
    public let month: Int
    /// 1...31, valid for `month` (29 February allowed).
    public let day: Int
    /// The birth year, or nil when the contact has none.
    public let year: Int?

    /// Returns nil when month and day cannot form a date in a leap year.
    public init?(month: Int, day: Int, year: Int? = nil) {
        guard (1...12).contains(month), day >= 1, day <= Self.maxDay(month: month) else { return nil }
        self.month = month
        self.day = day
        self.year = year
    }

    /// Reads Contacts-style components; nil when month or day is missing or invalid.
    public init?(components: DateComponents) {
        guard let month = components.month, let day = components.day else { return nil }
        // Contacts uses NSDateComponentUndefined for a missing year; anything implausible reads as none.
        let year = components.year.flatMap { (1...9999).contains($0) ? $0 : nil }
        self.init(month: month, day: day, year: year)
    }

    public var isLeapDay: Bool { month == 2 && day == 29 }

    private static func maxDay(month: Int) -> Int {
        switch month {
        case 2: 29
        case 4, 6, 9, 11: 30
        default: 31
        }
    }
}
