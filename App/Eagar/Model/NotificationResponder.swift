import EagarBrief
import EagarCalendar
import Foundation
import UserNotifications

/// A deadline notification's action button (FR-OS-05).
enum DeadlineNotificationAction: Equatable {
    case done, snooze

    init?(actionIdentifier: String) {
        switch actionIdentifier {
        case DeadlineNotificationPlan.doneActionIdentifier: self = .done
        case DeadlineNotificationPlan.snoozeActionIdentifier: self = .snooze
        default: return nil
        }
    }

    /// The deadline ID from a request identifier `deadline.<uuid>.<offset>` (or `.snooze`).
    static func deadlineID(fromRequestIdentifier identifier: String) -> UUID? {
        guard identifier.hasPrefix(DeadlineNotificationPlan.identifierPrefix) else { return nil }
        let rest = identifier.dropFirst(DeadlineNotificationPlan.identifierPrefix.count)
        return rest.split(separator: ".", maxSplits: 1).first.flatMap { UUID(uuidString: String($0)) }
    }
}

/// The notification categories Eagar registers at launch: the deadline category with Done and
/// Snooze, and the brief category with Open.
enum NotificationCategories {
    static let briefOpenActionIdentifier = "brief.open"

    static var all: Set<UNNotificationCategory> {
        [
            UNNotificationCategory(
                identifier: DeadlineNotificationPlan.categoryIdentifier,
                actions: [
                    UNNotificationAction(identifier: DeadlineNotificationPlan.doneActionIdentifier, title: String(localized: "Done"), options: []),
                    UNNotificationAction(identifier: DeadlineNotificationPlan.snoozeActionIdentifier, title: String(localized: "Snooze for 1 hour"), options: []),
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(
                identifier: BriefNotificationContent.categoryIdentifier,
                actions: [
                    UNNotificationAction(identifier: briefOpenActionIdentifier, title: String(localized: "Open"), options: [.foreground]),
                ],
                intentIdentifiers: [],
                options: []
            ),
        ]
    }
}

/// Handles notification actions and foreground presentation (FR-OS-05). Set as the
/// notification centre's delegate at launch; the centre holds it weakly, so the app keeps it.
@MainActor
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate {
    private let planner: PlannerModel

    init(planner: PlannerModel) {
        self.planner = planner
    }

    /// Registers the categories and becomes the centre's delegate.
    func install(on center: UNUserNotificationCenter = .current()) {
        center.setNotificationCategories(NotificationCategories.all)
        center.delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter, willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let category = response.notification.request.content.categoryIdentifier
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        await handle(category: category, requestIdentifier: identifier, actionIdentifier: action)
    }

    /// Done marks the deadline done; Snooze snoozes it for an hour, like the in-app "In 1 hour".
    /// Tapping a brief notification, or its Open action, shows the Today tab.
    func handle(category: String, requestIdentifier: String, actionIdentifier: String) async {
        switch category {
        case DeadlineNotificationPlan.categoryIdentifier:
            guard let action = DeadlineNotificationAction(actionIdentifier: actionIdentifier),
                  let id = DeadlineNotificationAction.deadlineID(fromRequestIdentifier: requestIdentifier)
            else { return }
            await planner.handleNotificationAction(action, deadlineID: id)
        case BriefNotificationContent.categoryIdentifier:
            if actionIdentifier == UNNotificationDefaultActionIdentifier || actionIdentifier == NotificationCategories.briefOpenActionIdentifier {
                NotificationCenter.default.post(name: .eagarShowBrief, object: nil)
            }
        default:
            break
        }
    }
}
