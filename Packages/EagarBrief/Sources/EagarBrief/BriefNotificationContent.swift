import EagarCore
import Foundation

/// The brief notification (FR-BRIEF-05, BD-04, BD-21). Content-free: counts only, for every
/// class, so nothing from a college item can appear on the Lock Screen.
public struct BriefNotificationContent: Sendable, Hashable {
    public enum Level: String, Sendable, Hashable {
        case passive, active
    }

    public let title: String
    public let body: String
    public let level: Level
    public let threadIdentifier: String

    public static let categoryIdentifier = "brief"

    public static func make(for brief: Brief) -> BriefNotificationContent {
        let items = brief.allItems
        let college = items.filter { $0.dataClass == .college }.count
        let title: String = switch brief.slot.kind {
        case .morning: String(localized: "Your morning brief", bundle: .module)
        case .midday: String(localized: "Your midday brief", bundle: .module)
        case .endOfDay: String(localized: "Your end-of-day brief", bundle: .module)
        }
        let body: String = if items.isEmpty {
            String(localized: "Nothing needs you right now.", bundle: .module)
        } else if college == 0 {
            String(localized: "Items to look at: \(items.count)", bundle: .module)
        } else {
            String(localized: "Items to look at: \(items.count), including college items: \(college)", bundle: .module)
        }
        let hasOverdue = brief.sections.contains { $0.kind == .overdue && !$0.items.isEmpty }
        return BriefNotificationContent(title: title, body: body, level: hasOverdue ? .active : .passive, threadIdentifier: "brief")
    }
}

/// Widget snapshot data (FR-BRIEF-06), shared with the widget extension through EagarCore.
public typealias BriefWidgetSnapshot = WidgetSnapshot

extension WidgetSnapshot {
    /// Builds the snapshot. College items never contribute a title, only to `collegeCount`.
    public static func make(for brief: Brief, maxLines: Int = 4) -> WidgetSnapshot {
        let items = brief.allItems
        let personal = items.filter { $0.dataClass != .college }
        let nextDeadline = items.filter { $0.kind == .deadline }.compactMap(\.start).min()
        return WidgetSnapshot(
            generatedAt: brief.generatedAt,
            lines: personal.prefix(maxLines).map { Line(title: $0.title, start: $0.start) },
            collegeCount: items.count - personal.count,
            nextDeadline: nextDeadline
        )
    }
}
