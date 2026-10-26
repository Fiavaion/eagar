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
///
/// Trials add `cancelSubscription` (opens the cancel page, FR-TRIAL-05) and
/// `confirmCancelled` (Mark confirms he cancelled); keep-in-touch nudges add `plan`,
/// `logContact` and `changeCadence` next to `snooze` (FR-PEOPLE-05).
public enum BriefAction: String, Sendable, Codable, CaseIterable {
    case open, done, snooze, reschedule, dismiss
    case cancelSubscription, confirmCancelled
    case plan, logContact, changeCadence

    /// Whether the action deals with the item (counts towards "fully actioned", SM2).
    /// Opening an item or its cancel page is not dealing with it.
    public var dealsWithItem: Bool { self != .open && self != .cancelSubscription }
}

/// What a brief item refers to. M2 adds trials, the monthly subscription summary and
/// keep-in-touch nudges; loans (cdbooking) are the next kind to join.
public enum BriefItemKind: String, Sendable, Codable {
    case event, deadline, trial, subscriptionSummary, nudge
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
    /// A second line shown under the title inside the app, e.g. "Cancel by Thu 29 Oct to
    /// avoid being charged €9.99". Same class and rules as `title`.
    public let detail: String?
    public var sourceID: SourceID? { nil }

    public init(
        id: String, kind: BriefItemKind, title: String, start: Date?, end: Date? = nil, isAllDay: Bool = false,
        dataClass: DataClass, actions: [BriefAction], detail: String? = nil
    ) {
        precondition(!actions.isEmpty, "FR-BRIEF-03: every brief item needs an action")
        self.id = id
        self.kind = kind
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.dataClass = dataClass
        self.actions = actions
        self.detail = detail
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

    public static let `default` = BriefPreferences(maxItems: [.today: 8, .deadlines: 6, .overdue: 6, .trials: 5, .keepInTouch: 3])

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

/// A trial or subscription as the brief needs it (FR-TRIAL-02, FR-TRIAL-06). The app maps
/// EagarMoney's `TrialSnapshot` and its next cancel-by to this.
public struct BriefTrial: Sendable, Hashable {
    public let id: String
    public let service: String
    public let price: Decimal
    /// ISO 4217 code.
    public let currencyCode: String
    /// The day Mark must cancel by to avoid `renewal`.
    public let cancelBy: Date
    public let renewal: Date
    /// The trial shows in the brief from this many days before cancel-by (its largest
    /// reminder day, 7 by default).
    public let windowDays: Int
    public let dataClass: DataClass

    public init(id: String, service: String, price: Decimal, currencyCode: String, cancelBy: Date, renewal: Date, windowDays: Int = 7, dataClass: DataClass) {
        self.id = id
        self.service = service
        self.price = price
        self.currencyCode = currencyCode
        self.cancelBy = cancelBy
        self.renewal = renewal
        self.windowDays = max(0, windowDays)
        self.dataClass = dataClass
    }
}

/// The monthly subscriptions summary as the brief needs it (FR-TRIAL-06). Shown on the 1st
/// of the month only.
public struct BriefSubscriptionSummary: Sendable, Hashable {
    public let activeCount: Int
    /// Monthly cost of everything active, per currency.
    public let monthlyTotals: [String: Decimal]
    /// Charges falling in this month.
    public let chargeCount: Int
    /// Their sum, per currency.
    public let chargeTotals: [String: Decimal]
    public let dataClass: DataClass

    public init(activeCount: Int, monthlyTotals: [String: Decimal], chargeCount: Int, chargeTotals: [String: Decimal], dataClass: DataClass) {
        self.activeCount = activeCount
        self.monthlyTotals = monthlyTotals
        self.chargeCount = chargeCount
        self.chargeTotals = chargeTotals
        self.dataClass = dataClass
    }
}

/// A keep-in-touch nudge as the brief needs it (FR-PEOPLE-05). `title` is the app's
/// deterministic phrasing ("Thursday evening is free; Aoife: 7 weeks"). A nudge placed in a
/// slot after a college event is `college`: shown in the app, counted only elsewhere.
public struct BriefNudge: Sendable, Hashable {
    public let id: String
    public let title: String
    public let slot: DateInterval
    public let dataClass: DataClass

    public init(id: String, title: String, slot: DateInterval, dataClass: DataClass) {
        self.id = id
        self.title = title
        self.slot = slot
        self.dataClass = dataClass
    }
}

/// Everything beyond the calendar and deadlines that feeds the brief. Each source fills its
/// own section; a new source (cdbooking loans next, `.loans`) adds a field here and a section
/// builder in ``BriefComposer``, so callers that don't have it yet keep compiling.
public struct BriefSources: Sendable, Hashable {
    public var trials: [BriefTrial]
    public var subscriptionSummary: BriefSubscriptionSummary?
    public var nudges: [BriefNudge]

    public init(trials: [BriefTrial] = [], subscriptionSummary: BriefSubscriptionSummary? = nil, nudges: [BriefNudge] = []) {
        self.trials = trials
        self.subscriptionSummary = subscriptionSummary
        self.nudges = nudges
    }

    public static let none = BriefSources()
}
