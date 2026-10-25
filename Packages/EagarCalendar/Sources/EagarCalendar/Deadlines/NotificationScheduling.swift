import EagarCore
import Foundation
import UserNotifications

/// The notification-centre surface the deadline sync uses, behind a protocol for tests.
public protocol NotificationScheduling: Sendable {
    func pendingIdentifiers() async -> [String]
    func add(_ planned: PlannedNotification) async throws
    func remove(identifiers: [String]) async
    func requestAuthorization() async throws -> Bool
}

/// `UNUserNotificationCenter` implementation.
public struct UserNotificationScheduler: NotificationScheduling {
    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    private var center: UNUserNotificationCenter { .current() }

    public func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func add(_ planned: PlannedNotification) async throws {
        try await center.add(Self.request(for: planned, calendar: calendar))
    }

    public func remove(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// Asks for permission. Categories are registered once at launch by the app, for every
    /// notification kind together; setting them here would replace the others.
    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// The `deadline` category with Done and Snooze actions.
    static func category() -> UNNotificationCategory {
        UNNotificationCategory(
            identifier: DeadlineNotificationPlan.categoryIdentifier,
            actions: [
                UNNotificationAction(
                    identifier: DeadlineNotificationPlan.doneActionIdentifier,
                    title: String(localized: "Done", bundle: .module), options: []),
                UNNotificationAction(
                    identifier: DeadlineNotificationPlan.snoozeActionIdentifier,
                    title: String(localized: "Snooze", bundle: .module), options: []),
            ],
            intentIdentifiers: [],
            options: []
        )
    }

    /// Maps a plan entry to a request with an absolute calendar trigger.
    static func request(for planned: PlannedNotification, calendar: Calendar) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.categoryIdentifier = planned.categoryIdentifier
        content.threadIdentifier = planned.threadIdentifier
        content.sound = .default
        content.interruptionLevel = switch planned.interruptionLevel {
        case .active: .active
        case .timeSensitive: .timeSensitive
        }
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: planned.fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger)
    }
}

/// Reconciles planned notifications with those pending (FR-DL-02).
public enum DeadlineNotificationSync {
    private static let log = EagarLog(.app)

    /// Removes stale `deadline.` requests and adds missing ones. Requests that are already
    /// pending are left alone; the identifier carries deadline and offset, not content.
    public static func sync(
        deadlines: [DeadlineSnapshot], now: Date, scheduler: some NotificationScheduling, calendar: Calendar = .current
    ) async {
        let planned = DeadlineNotificationPlan.plan(deadlines, now: now, calendar: calendar)
        let wanted = Set(planned.map(\.id))
        let pending = Set(await scheduler.pendingIdentifiers().filter { $0.hasPrefix(DeadlineNotificationPlan.identifierPrefix) })
        let stale = pending.subtracting(wanted).sorted()
        if !stale.isEmpty { await scheduler.remove(identifiers: stale) }
        // Re-add every planned request: adding with an existing identifier replaces it, so an
        // edited title or due date never leaves a stale notification behind.
        for item in planned {
            do {
                try await scheduler.add(item)
            } catch {
                log.error("could not schedule a deadline notification")
            }
        }
    }
}
