import EagarCore
import Foundation
import Observation

/// One week's Screen Time figures for the apps Eagar replaces (Appendix D, D1 / SM1),
/// entered by hand. Content-free: numbers and a week only.
struct ScreenTimeEntry: Codable, Equatable, Identifiable {
    /// Start of the week (per the calendar's first weekday).
    let weekStart: Date
    var minutes: Int
    var pickups: Int?
    var id: Date { weekStart }
}

/// Manual weekly Screen Time entries (FR-GOV-01, M2 part). Kept on this device in
/// UserDefaults: personal, content-free and not synced (the pilot baseline is per device).
@MainActor
@Observable
final class PilotMetricsModel {
    private(set) var entries: [ScreenTimeEntry] = []

    private let defaults: UserDefaults
    private let calendar: Calendar
    private let clock: any EagarClock
    static let key = "pilot.screenTime"

    init(defaults: UserDefaults, clock: any EagarClock, calendar: Calendar) {
        self.defaults = defaults
        self.clock = clock
        self.calendar = calendar
        entries = Self.load(from: defaults)
    }

    /// The start of the week containing `date`.
    func weekStart(for date: Date) -> Date {
        calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    /// Last week, the usual one to enter (Screen Time shows complete weeks).
    var lastWeekStart: Date {
        weekStart(for: calendar.date(byAdding: .day, value: -7, to: clock.now()) ?? clock.now())
    }

    /// Adds or replaces the entry for the week containing `week`.
    func record(week: Date, minutes: Int, pickups: Int?) {
        let start = weekStart(for: week)
        var all = entries.filter { $0.weekStart != start }
        all.append(ScreenTimeEntry(weekStart: start, minutes: max(0, minutes), pickups: pickups.map { max(0, $0) }))
        entries = all.sorted { $0.weekStart > $1.weekStart }
        save()
    }

    func delete(_ entry: ScreenTimeEntry) {
        entries.removeAll { $0.weekStart == entry.weekStart }
        save()
    }

    /// Average minutes per week over the entries, if any.
    var averageMinutes: Int? {
        entries.isEmpty ? nil : entries.map(\.minutes).reduce(0, +) / entries.count
    }

    private func save() {
        do {
            defaults.set(try JSONEncoder().encode(entries), forKey: Self.key)
        } catch {
            EagarLog(.app).error("screen time entries could not be saved")
        }
    }

    private static func load(from defaults: UserDefaults) -> [ScreenTimeEntry] {
        guard let data = defaults.data(forKey: key) else { return [] }
        do {
            return try JSONDecoder().decode([ScreenTimeEntry].self, from: data).sorted { $0.weekStart > $1.weekStart }
        } catch {
            EagarLog(.app).error("screen time entries unreadable; kept a backup")
            defaults.set(data, forKey: key + ".unreadable")
            defaults.removeObject(forKey: key)
            return []
        }
    }
}
