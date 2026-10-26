import EagarCalendar
import EagarCore
import Foundation

/// A fixed Dublin calendar and the week of Monday 4 January 2027, for nudge tests.
enum NudgeFixtures {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
        calendar.firstWeekday = 2
        calendar.locale = Locale(identifier: "en_IE")
        return calendar
    }()

    /// Monday 4 January 2027, 00:00 Dublin.
    static let weekStart = calendar.date(from: DateComponents(year: 2027, month: 1, day: 4))!
    static let week = DateInterval(start: weekStart, end: calendar.date(byAdding: .day, value: 7, to: weekStart)!)

    /// `day` days after Monday (0 = Monday), at `hour`:`minute` local.
    static func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        let date = calendar.date(byAdding: .day, value: day, to: weekStart)!
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date)!
    }

    static func daysAgo(_ days: Int, from date: Date = weekStart) -> Date {
        calendar.date(byAdding: .day, value: -days, to: date)!
    }

    /// One free evening, 18:00 to 22:00, on each day of the week.
    static func freeEvenings(_ dataClass: DataClass = .personal) -> [FreeSlot] {
        (0..<7).map { FreeSlot(interval: DateInterval(start: at($0, 18), end: at($0, 22)), dataClass: dataClass) }
    }
}
