import EagarCalendar
import EagarCore
import Foundation

/// Deterministic brief assembly (FR-BRIEF-01, NFR-PERF-03). No AI, no I/O.
public enum BriefComposer {
    /// - Parameters:
    ///   - events: today's events, already classified by calendar tag. Events on calendars Mark
    ///     excluded from the brief should be filtered out by the caller.
    ///   - deadlines: open deadlines.
    ///   - horizon: how far ahead the deadlines section looks.
    public static func compose(
        slot: BriefSlot,
        now: Date,
        events: [ClassifiedEvent],
        deadlines: [BriefDeadline],
        preferences: BriefPreferences = .default,
        calendar: Calendar = .current,
        horizon: TimeInterval = 7 * 86_400
    ) -> Brief {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)

        let todayItems = events
            .filter { $0.event.end > now && $0.event.start < dayEnd }
            .sorted { ($0.event.isAllDay ? 0 : 1, $0.event.start) < ($1.event.isAllDay ? 0 : 1, $1.event.start) }
            .map { classified in
                BriefItem(
                    id: "event.\(classified.event.id)", kind: .event, title: classified.event.title,
                    start: classified.event.start, end: classified.event.end, isAllDay: classified.event.isAllDay,
                    dataClass: classified.dataClass, actions: [.open, .dismiss]
                )
            }

        let overdue = deadlines.filter { $0.dueAt <= now }.sorted { $0.dueAt < $1.dueAt }
        let upcoming = deadlines.filter { $0.dueAt > now && $0.dueAt <= now.addingTimeInterval(horizon) }.sorted { $0.dueAt < $1.dueAt }

        func deadlineItem(_ deadline: BriefDeadline, overdue: Bool) -> BriefItem {
            BriefItem(
                id: "deadline.\(deadline.id)", kind: .deadline, title: deadline.title,
                start: deadline.dueAt, isAllDay: deadline.isAllDay, dataClass: deadline.dataClass,
                actions: overdue ? [.done, .snooze, .reschedule] : [.done, .snooze, .open]
            )
        }

        let content: [BriefSectionKind: [BriefItem]] = [
            .overdue: overdue.map { deadlineItem($0, overdue: true) },
            .today: todayItems,
            .deadlines: upcoming.map { deadlineItem($0, overdue: false) },
        ]

        let sections = preferences.orderedKinds().compactMap { kind -> BriefSection? in
            guard let items = content[kind], !items.isEmpty else { return nil }
            let limit = preferences.maxItems[kind] ?? items.count
            return BriefSection(kind: kind, items: Array(items.prefix(limit)), hiddenCount: max(0, items.count - limit))
        }
        let id = "brief.\(slot.kind.rawValue).\(Int(dayStart.timeIntervalSince1970))"
        return Brief(id: id, slot: slot, generatedAt: now, sections: sections)
    }
}
