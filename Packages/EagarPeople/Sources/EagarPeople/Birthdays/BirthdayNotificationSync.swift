import EagarCore
import Foundation
import UserNotifications

/// The notification-centre surface birthday reminders use, behind a protocol for tests.
public protocol BirthdayNotificationScheduling: Sendable {
    func pendingIdentifiers() async -> [String]
    func add(_ planned: PlannedBirthdayNotification) async throws
    func remove(identifiers: [String]) async
}

/// `UNUserNotificationCenter` implementation. Authorisation and categories are the app's,
/// requested once for every notification kind.
public struct UserBirthdayNotificationScheduler: BirthdayNotificationScheduling {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    private var center: UNUserNotificationCenter { .current() }

    public func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func add(_ planned: PlannedBirthdayNotification) async throws {
        try await center.add(Self.request(for: planned, calendar: calendar))
    }

    public func remove(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// A request with an absolute calendar trigger at the planned local time.
    static func request(for planned: PlannedBirthdayNotification, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.categoryIdentifier = planned.categoryIdentifier
        content.threadIdentifier = planned.threadIdentifier
        content.sound = .default
        content.interruptionLevel = .active
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: planned.fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger)
    }
}

/// Reconciles planned birthday reminders with those pending (FR-PEOPLE-06).
public enum BirthdayNotificationSync {
    private static let log = EagarLog(.app)

    /// Removes stale `birthday.` requests and (re-)adds every planned one, so a renamed person
    /// or changed birthday never leaves an old notification behind. Other prefixes are untouched.
    public static func sync(
        people: [PersonSnapshot], now: Date, scheduler: some BirthdayNotificationScheduling, calendar: Calendar = .current
    ) async {
        let planned = BirthdayNotificationPlan.plan(people, now: now, calendar: calendar)
        let wanted = Set(planned.map(\.id))
        let pending = Set(await scheduler.pendingIdentifiers().filter { $0.hasPrefix(BirthdayNotificationPlan.identifierPrefix) })
        let stale = pending.subtracting(wanted).sorted()
        if !stale.isEmpty { await scheduler.remove(identifiers: stale) }
        for item in planned {
            do {
                try await scheduler.add(item)
            } catch {
                log.error("could not schedule a birthday notification")
            }
        }
    }
}
