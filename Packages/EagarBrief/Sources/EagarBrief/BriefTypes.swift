import EagarCore
import Foundation

/// When a brief is due (FR-BRIEF-01). Times are local wall-clock hours and minutes.
public struct BriefSlot: Sendable, Hashable, Codable, Identifiable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case morning, midday, endOfDay
    }

    public let kind: Kind
    public let hour: Int
    public let minute: Int
    public var id: Kind { kind }

    public init(kind: Kind, hour: Int, minute: Int = 0) {
        self.kind = kind
        self.hour = hour
        self.minute = minute
    }

    /// Default: a morning brief at 08:00.
    public static let defaultSlots = [BriefSlot(kind: .morning, hour: 8)]

    /// The slot's time on the day containing `date`.
    public func time(on date: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: date) ?? date
    }
}

/// Brief sections, in default order (FR-BRIEF-01). M1 fills `overdue`, `today` and `deadlines`;
/// later milestones fill the rest, so the order and preferences are stable from the start.
public enum BriefSectionKind: String, Sendable, Codable, CaseIterable, LogSafe {
    case overdue, today, deadlines, loans, trials, mail, approvals, waiting, keepInTouch, media

    public var logDescription: String { rawValue }
}

/// What an item can do (FR-BRIEF-03: every item has at least one action).
public enum BriefAction: String, Sendable, Codable, CaseIterable {
    case open, done, snooze, reschedule, dismiss
}

public enum BriefItemKind: String, Sendable, Codable {
    case event, deadline
}

/// One brief line. `title` is shown only inside the app; notifications and widgets use
/// ``BriefNotificationContent`` and counts for college items (FR-BRIEF-05/06).
public struct BriefItem: Sendable, Hashable, Identifiable, Classified {
    public let id: String
    public let kind: BriefItemKind
    public let title: String
    public let start: Date?
    public let end: Date?
    public let isAllDay: Bool
    public let dataClass: DataClass
    public let actions: [BriefAction]
    public var sourceID: SourceID? { nil }

    public init(id: String, kind: BriefItemKind, title: String, start: Date?, end: Date? = nil, isAllDay: Bool = false, dataClass: DataClass, actions: [BriefAction]) {
        precondition(!actions.isEmpty, "FR-BRIEF-03: every brief item needs an action")
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.dataClass = dataClass
        self.actions = actions
    }
}

public struct BriefSection: Sendable, Hashable, Identifiable {
    public let kind: BriefSectionKind
    public let items: [BriefItem]
    /// Items left out by the section's size limit.
    public let hiddenCount: Int
    public var id: BriefSectionKind { kind }

    /// The section's class: the most restrictive of its items.
    public var dataClass: DataClass { DataClass.max(of: items.map(\.dataClass)) }
}

/// A composed brief. Deterministic; AI phrasing is attached separately (FR-BRIEF-04).
public struct Brief: Sendable, Hashable, Identifiable {
    public let id: String
    public let slot: BriefSlot
    public let generatedAt: Date
    public let sections: [BriefSection]

    public var allItems: [BriefItem] { sections.flatMap(\.items) }
    public var isEmpty: Bool { sections.allSatisfy { $0.items.isEmpty } }
}

/// Mark's steering (FR-BRIEF-07): order, hidden sections and per-section size.
public struct BriefPreferences: Sendable, Hashable, Codable {
    public var order: [BriefSectionKind]
    public var hidden: Set<BriefSectionKind>
    public var maxItems: [BriefSectionKind: Int]

    public init(order: [BriefSectionKind] = BriefSectionKind.allCases, hidden: Set<BriefSectionKind> = [], maxItems: [BriefSectionKind: Int] = [:]) {
        self.order = order
        self.hidden = hidden
        self.maxItems = maxItems
    }

    public static let `default` = BriefPreferences(maxItems: [.today: 8, .deadlines: 6, .overdue: 6])

    /// Sections in display order. Overdue always comes first when present (FR-DL-04).
    func orderedKinds() -> [BriefSectionKind] {
        var kinds = order.filter { !hidden.contains($0) }
        for kind in BriefSectionKind.allCases where !kinds.contains(kind) && !hidden.contains(kind) { kinds.append(kind) }
        if let index = kinds.firstIndex(of: .overdue) {
            kinds.remove(at: index)
            kinds.insert(.overdue, at: 0)
        }
        return kinds
    }
}

/// A deadline as the brief needs it. The app maps `DeadlineSnapshot` to this.
public struct BriefDeadline: Sendable, Hashable {
    public let id: String
    public let title: String
    public let dueAt: Date
    public let isAllDay: Bool
    public let dataClass: DataClass

    public init(id: String, title: String, dueAt: Date, isAllDay: Bool = false, dataClass: DataClass) {
        self.id = id
        self.title = title
        self.dueAt = dueAt
        self.isAllDay = isAllDay
        self.dataClass = dataClass
    }
}
