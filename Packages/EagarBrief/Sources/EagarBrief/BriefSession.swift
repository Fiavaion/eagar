import EagarCore
import EagarStore
import EagarSuggest
import Foundation

/// Tracks one opened brief: logs opening, each action and, once every item has been acted on,
/// the time from opening to fully actioned (FR-BRIEF-08, SM2). Thumbs feed the event log
/// (FR-BRIEF-07). Entries are content-free: kinds, opaque IDs and a duration.
public actor BriefSession {
    private let brief: Brief
    private let log: EventLog
    private let clock: any EagarClock
    private var openedAt: Date?
    private var remaining: Set<String>
    private var completed = false

    public init(brief: Brief, log: EventLog, clock: any EagarClock = SystemClock()) {
        self.brief = brief
        self.log = log
        self.clock = clock
        remaining = Set(brief.allItems.map(\.id))
    }

    /// The class of brief-level entries: the most restrictive of its items, so an entry about a
    /// brief containing college items stays in CollegeStore.
    private var briefClass: DataClass { DataClass.max(of: brief.allItems.map(\.dataClass)) }

    public func opened() async throws(StoreError) {
        guard openedAt == nil else { return }
        openedAt = clock.now()
        try await log.record(.briefOpened, subject: brief.id, dataClass: briefClass)
    }

    /// Records an action on an item. Returns `true` when this completed the brief.
    @discardableResult
    public func acted(_ action: BriefAction, on itemID: String) async throws(StoreError) -> Bool {
        guard let item = brief.allItems.first(where: { $0.id == itemID }) else { return false }
        let kind: EventLogKind = switch action {
        case .open: .itemOpened
        case .done: .itemDone
        case .snooze: .itemSnoozed
        case .reschedule: .itemRescheduled
        case .dismiss: .itemDismissed
        }
        try await log.record(kind, subject: itemID, dataClass: item.dataClass)
        // Opening an item isn't dealing with it; every other action is.
        if action != .open { remaining.remove(itemID) }
        guard remaining.isEmpty, !completed, let openedAt else { return false }
        completed = true
        try await log.record(.briefCompleted, subject: brief.id, value: clock.now().timeIntervalSince(openedAt), dataClass: briefClass)
        return true
    }

    public func rated(_ itemID: String, helpful: Bool) async throws(StoreError) {
        guard let item = brief.allItems.first(where: { $0.id == itemID }) else { return }
        try await log.record(helpful ? .thumbsUp : .thumbsDown, subject: itemID, dataClass: item.dataClass)
    }
}
