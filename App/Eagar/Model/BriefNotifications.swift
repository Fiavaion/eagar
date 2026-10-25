import EagarBrief
import EagarCore
import Foundation
import UserNotifications

/// Schedules the brief's local notification (FR-BRIEF-02, FR-BRIEF-05), behind a protocol so
/// tests can use a spy.
protocol BriefNotificationScheduling: Sendable {
    /// Pending identifiers that start with ``BriefNotificationID/prefix``.
    func pendingBriefIdentifiers() async -> [String]
    /// Adds or replaces the request with `identifier`, firing at `date`.
    func schedule(_ content: BriefNotificationContent, at date: Date, identifier: String) async throws
    func remove(identifiers: [String]) async
}

/// Identifiers for brief notifications: `brief.<slot>.<yyyy-MM-dd>`.
enum BriefNotificationID {
    static let prefix = "brief."

    static func make(slot: BriefSlot.Kind, day: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: day)
        let date = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
        return "\(prefix)\(slot.rawValue).\(date)"
    }
}

/// `UNUserNotificationCenter` implementation. Adds nothing until Mark has allowed notifications,
/// so a test host or a fresh install never queues requests silently.
struct UserBriefNotificationScheduler: BriefNotificationScheduling {
    private var center: UNUserNotificationCenter { .current() }

    func pendingBriefIdentifiers() async -> [String] {
        await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(BriefNotificationID.prefix) }
    }

    func schedule(_ content: BriefNotificationContent, at date: Date, identifier: String) async throws {
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }
        let body = UNMutableNotificationContent()
        body.title = content.title
        body.body = content.body
        body.categoryIdentifier = BriefNotificationContent.categoryIdentifier
        body.threadIdentifier = content.threadIdentifier
        body.interruptionLevel = switch content.level {
        case .passive: .passive
        case .active: .active
        }
        var components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        components.calendar = Calendar.current
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        try await center.add(UNNotificationRequest(identifier: identifier, content: body, trigger: trigger))
    }

    func remove(identifiers: [String]) async {
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }
}

/// A notification-centre error as logs may show it: the `UNError` code, or "other".
enum NotificationFailureKind: LogSafe {
    case notifications(code: Int)
    case other

    init(_ error: any Error) {
        let error = error as NSError
        self = error.domain == UNErrorDomain ? .notifications(code: error.code) : .other
    }

    var logDescription: String {
        switch self {
        case let .notifications(code): "UNError(\(code))"
        case .other: "other"
        }
    }
}
