import EagarCore
import Foundation

/// How urgently a planned notification interrupts (BD-21).
public enum PlannedInterruptionLevel: String, Sendable, Hashable {
    case active, timeSensitive
}

/// A local notification the planner wants scheduled (FR-DL-02).
public struct PlannedNotification: Sendable, Hashable, Identifiable {
    public let id: String
    public let deadlineID: UUID
    public let offsetMinutes: Int
    public let fireDate: Date
    public let title: String
    public let body: String
    public let interruptionLevel: PlannedInterruptionLevel
    public let categoryIdentifier: String
    public let threadIdentifier: String
}

/// Pure planner from deadline snapshots to notifications. No server, no model objects.
public enum DeadlineNotificationPlan {
    public static let identifierPrefix = "deadline."
    public static let categoryIdentifier = "deadline"
    public static let doneActionIdentifier = "deadline.done"
    public static let snoozeActionIdentifier = "deadline.snooze"
    /// Offsets at or under this many minutes are genuine, imminent deadlines (BD-21).
    public static let timeSensitiveMaxOffsetMinutes = 120
    /// All-day deadlines fire at this local hour when the offset is a day or more.
    public static let allDayFireHour = 9

    public static func identifier(deadlineID: UUID, offsetMinutes: Int) -> String {
        "\(identifierPrefix)\(deadlineID.uuidString).\(offsetMinutes)"
    }

    public static func plan(
        _ deadlines: [DeadlineSnapshot], now: Date, calendar: Calendar = .current
    ) -> [PlannedNotification] {
        deadlines.flatMap { plan(for: $0, now: now, calendar: calendar) }
    }

    static func plan(for deadline: DeadlineSnapshot, now: Date, calendar: Calendar) -> [PlannedNotification] {
        guard deadline.status == .open else { return [] }
        return offsetNotifications(for: deadline, now: now, calendar: calendar) + snoozeNotification(for: deadline, now: now)
    }

    /// One reminder when a snooze ends, so snoozing means "remind me later", not "forget".
    static func snoozeNotification(for deadline: DeadlineSnapshot, now: Date) -> [PlannedNotification] {
        guard let snoozed = deadline.snoozedUntil, snoozed > now else { return [] }
        let minutesLeft = max(0, Int(deadline.dueAt.timeIntervalSince(snoozed) / 60))
        let (title, body) = content(for: deadline, offsetMinutes: minutesLeft)
        return [PlannedNotification(
            id: "\(identifierPrefix)\(deadline.id.uuidString).snooze",
            deadlineID: deadline.id,
            offsetMinutes: minutesLeft,
            fireDate: snoozed,
            title: title,
            body: body,
            interruptionLevel: minutesLeft <= timeSensitiveMaxOffsetMinutes ? .timeSensitive : .active,
            categoryIdentifier: categoryIdentifier,
            threadIdentifier: "deadline.\(deadline.id.uuidString)"
        )]
    }

    static func offsetNotifications(for deadline: DeadlineSnapshot, now: Date, calendar: Calendar) -> [PlannedNotification] {
        var seen = Set<Int>()
        return deadline.reminderOffsetsMinutes.sorted(by: >).compactMap { offset in
            guard offset >= 0, seen.insert(offset).inserted else { return nil }
            guard let fire = fireDate(for: deadline, offsetMinutes: offset, calendar: calendar), fire > now else { return nil }
            if let snoozed = deadline.snoozedUntil, snoozed > fire { return nil }
            let (title, body) = content(for: deadline, offsetMinutes: offset)
            return PlannedNotification(
                id: identifier(deadlineID: deadline.id, offsetMinutes: offset),
                deadlineID: deadline.id,
                offsetMinutes: offset,
                fireDate: fire,
                title: title,
                body: body,
                interruptionLevel: offset <= timeSensitiveMaxOffsetMinutes ? .timeSensitive : .active,
                categoryIdentifier: categoryIdentifier,
                threadIdentifier: "deadline.\(deadline.id.uuidString)"
            )
        }
    }

    /// Whole days are subtracted with calendar arithmetic, so the local time of day survives a
    /// DST change; the remainder is subtracted as elapsed minutes. All-day deadlines whose
    /// offset is a day or more fire at 09:00 local.
    static func fireDate(for deadline: DeadlineSnapshot, offsetMinutes: Int, calendar: Calendar) -> Date? {
        let days = offsetMinutes / 1440
        let remainder = offsetMinutes % 1440
        if deadline.isAllDay && days >= 1 {
            let dueDay = calendar.startOfDay(for: deadline.dueAt)
            guard let day = calendar.date(byAdding: .day, value: -days, to: dueDay),
                  let nine = calendar.date(bySettingHour: allDayFireHour, minute: 0, second: 0, of: day)
            else { return nil }
            return nine.addingTimeInterval(-Double(remainder) * 60)
        }
        guard let shifted = calendar.date(byAdding: .day, value: -days, to: deadline.dueAt) else { return nil }
        return shifted.addingTimeInterval(-Double(remainder) * 60)
    }

    /// College deadlines are content-free (BD-04): generic title, no deadline title anywhere.
    private static func content(for deadline: DeadlineSnapshot, offsetMinutes: Int) -> (title: String, body: String) {
        let isCollege = deadline.dataClass == .college
        if offsetMinutes == 0 {
            return isCollege
                ? (String(localized: "College deadline", bundle: .module), String(localized: "A college deadline is due now", bundle: .module))
                : (deadline.title, String(localized: "Due now", bundle: .module))
        }
        let span = Duration.seconds(offsetMinutes * 60)
            .formatted(.units(allowed: [.weeks, .days, .hours, .minutes], width: .wide))
        return isCollege
            ? (String(localized: "College deadline", bundle: .module), String(localized: "A college deadline is due in \(span)", bundle: .module))
            : (deadline.title, String(localized: "Due in \(span)", bundle: .module))
    }
}
