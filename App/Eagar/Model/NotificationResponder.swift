import EagarBrief
import EagarCalendar
import EagarMoney
import EagarPeople
import Foundation
import UserNotifications
#if os(iOS)
import UIKit
#else
import AppKit
#endif

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

/// The notification categories Eagar registers at launch, all at once (D-021): the deadline
/// category with Done and Snooze, the brief category with Open, the trial category with Cancel
/// and "I've cancelled" (FR-TRIAL-05), and the birthday category (FR-PEOPLE-06).
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
                identifier: TrialReminderPlan.categoryIdentifier,
                actions: [
                    UNNotificationAction(identifier: TrialReminderPlan.cancelActionIdentifier, title: String(localized: "Cancel…"), options: [.foreground]),
                    UNNotificationAction(identifier: TrialReminderPlan.confirmCancelledActionIdentifier, title: String(localized: "I've cancelled it"), options: [.authenticationRequired]),
                ],
                intentIdentifiers: [],
                options: []
            ),
            UNNotificationCategory(identifier: BirthdayNotificationPlan.categoryIdentifier, actions: [], intentIdentifiers: [], options: []),
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
    private let money: MoneyModel
    private let openURL: @MainActor (URL) -> Void

    init(planner: PlannerModel, money: MoneyModel, openURL: @escaping @MainActor (URL) -> Void = ExternalURL.open) {
        self.planner = planner
        self.money = money
        self.openURL = openURL
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
        let content = response.notification.request.content
        let identifier = response.notification.request.identifier
        let action = response.actionIdentifier
        let cancelTarget = content.userInfo[UserTrialReminderScheduler.cancelTargetKey] as? String
        await handle(category: content.categoryIdentifier, requestIdentifier: identifier, actionIdentifier: action, cancelTarget: cancelTarget)
    }

    /// Done marks the deadline done; Snooze snoozes it for an hour, like the in-app "In 1 hour".
    /// Tapping a brief notification, or its Open action, shows the Today tab.
    /// A trial's Cancel opens its cancel page (never changing the status); "I've cancelled it"
    /// records the cancellation; tapping shows Subscriptions. Tapping a birthday shows Today.
    func handle(category: String, requestIdentifier: String, actionIdentifier: String, cancelTarget: String? = nil) async {
        switch category {
        case DeadlineNotificationPlan.categoryIdentifier:
            guard let action = DeadlineNotificationAction(actionIdentifier: actionIdentifier),
                  let id = DeadlineNotificationAction.deadlineID(fromRequestIdentifier: requestIdentifier)
            else { return }
            await planner.handleNotificationAction(action, deadlineID: id)
        case TrialReminderPlan.categoryIdentifier:
            guard let id = TrialReminderSync.trialID(fromRequestIdentifier: requestIdentifier) else { return }
            switch actionIdentifier {
            case TrialReminderPlan.cancelActionIdentifier:
                let fallback = money.cancelTarget(id)
                openURL(cancelTarget.flatMap(URL.init(string:)).map { Self.safeCancelTarget($0) ?? fallback } ?? fallback)
                NotificationCenter.default.post(name: .eagarShowTab, object: RootTab.subscriptions.rawValue)
            case TrialReminderPlan.confirmCancelledActionIdentifier:
                await money.handleConfirmCancelledAction(trialID: id)
            default:
                NotificationCenter.default.post(name: .eagarShowTab, object: RootTab.subscriptions.rawValue)
            }
        case BriefNotificationContent.categoryIdentifier:
            if actionIdentifier == UNNotificationDefaultActionIdentifier || actionIdentifier == NotificationCategories.briefOpenActionIdentifier {
                NotificationCenter.default.post(name: .eagarShowBrief, object: nil)
            }
        default:
            break
        }
    }
}

extension NotificationResponder {
    /// Only web links are opened from a notification, as in `TrialCancelAction`.
    static func safeCancelTarget(_ url: URL) -> URL? {
        guard let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http", url.host() != nil else { return nil }
        return url
    }
}

/// Opens a web page outside SwiftUI (notification actions).
enum ExternalURL {
    @MainActor
    static func open(_ url: URL) {
        #if os(iOS)
        UIApplication.shared.open(url)
        #else
        NSWorkspace.shared.open(url)
        #endif
    }
}
