import EagarCore
import Foundation
import UserNotifications

/// The notification-centre surface trial reminders use, behind a protocol for tests.
public protocol TrialReminderScheduling: Sendable {
    func pendingIdentifiers() async -> [String]
    func add(_ planned: PlannedTrialReminder) async throws
    func remove(identifiers: [String]) async
}

/// `UNUserNotificationCenter` implementation. Authorisation and the `trial` category are the
/// app's, registered once at launch for every notification kind (D-021).
public struct UserTrialReminderScheduler: TrialReminderScheduling {
    /// `userInfo` key holding the Cancel action's target URL string (FR-TRIAL-05).
    public static let cancelTargetKey = "cancelTarget"
    /// `userInfo` key holding the trial's UUID string.
    public static let trialIDKey = "trialID"

    private let calendar: Calendar

    public init(calendar: Calendar = .current) {
        self.calendar = calendar
    }

    private var center: UNUserNotificationCenter { .current() }

    public func pendingIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier)
    }

    public func add(_ planned: PlannedTrialReminder) async throws {
        try await center.add(Self.request(for: planned, calendar: calendar))
    }

    public func remove(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    /// A request with an absolute calendar trigger at the planned local time. The user info
    /// carries only the trial's UUID and the cancel page, never the service name.
    static func request(for planned: PlannedTrialReminder, calendar: Calendar) -> UNNotificationRequest {
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
        content.userInfo = [
            cancelTargetKey: planned.cancelTarget.absoluteString,
            trialIDKey: planned.trialID.uuidString,
        ]
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: planned.fireDate)
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger)
    }
}

/// Reconciles planned trial reminders with those pending (FR-TRIAL-02).
public enum TrialReminderSync {
    private static let log = EagarLog(.money)

    /// Removes stale `trial.` requests (cancelled, deleted or rescheduled trials) and
    /// (re-)adds every planned one, so an edited price or date never leaves an old reminder
    /// behind. Requests with other prefixes are untouched.
    public static func sync(
        trials: [TrialSnapshot], now: Date, scheduler: some TrialReminderScheduling,
        calendar: Calendar = .current, locale: Locale = .current
    ) async {
        let planned = TrialReminderPlan.plan(trials, now: now, calendar: calendar, locale: locale)
        let wanted = Set(planned.map(\.id))
        let pending = Set(await scheduler.pendingIdentifiers().filter { $0.hasPrefix(TrialReminderPlan.identifierPrefix) })
        let stale = pending.subtracting(wanted).sorted()
        if !stale.isEmpty { await scheduler.remove(identifiers: stale) }
        var failures = 0
        for item in planned {
            do {
                try await scheduler.add(item)
            } catch {
                failures += 1
            }
        }
        if failures > 0 { log.error("could not schedule \(failures) trial reminders") }
    }

    /// The trial UUID from a request identifier `trial.<uuid>.<days>`.
    public static func trialID(fromRequestIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(TrialReminderPlan.identifierPrefix) else { return nil }
        let rest = identifier.dropFirst(TrialReminderPlan.identifierPrefix.count)
        return rest.split(separator: ".", maxSplits: 1).first.flatMap { UUID(uuidString: String($0)) }
    }
}
