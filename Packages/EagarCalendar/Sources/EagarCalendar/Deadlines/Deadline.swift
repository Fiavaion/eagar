import EagarCore
import Foundation
import SwiftData

/// Where a deadline came from (FR-DL-01). Only `manual` is produced in M1.
public enum DeadlineOrigin: String, Codable, Sendable, CaseIterable {
    case manual, commitment, canvas, booking, trial
}

public enum DeadlineStatus: String, Codable, Sendable, CaseIterable {
    case open, done
}

/// The default notification offsets: one day and two hours before the due time.
public let defaultDeadlineOffsetsMinutes = [1440, 120]

/// A deadline (FR-DL-01). CloudKit-compatible: every attribute defaulted or optional, no
/// unique constraints, no relationships.
///
/// Logical uniqueness by `deadlineUUID` is the caller's concern (upsert code), not the schema's.
@Model
public final class Deadline: Classified {
    public var deadlineUUID: UUID = UUID()
    public var title: String = ""
    public var dueAt: Date = Date.distantFuture
    public var isAllDay: Bool = false
    public var originRaw: String = DeadlineOrigin.manual.rawValue
    public var reminderOffsetsMinutes: [Int] = defaultDeadlineOffsetsMinutes
    public var dataClassRaw: String = DataClass.college.rawValue
    public var sourceUUID: UUID?
    public var statusRaw: String = DeadlineStatus.open.rawValue
    public var snoozedUntil: Date?
    public var completedAt: Date?
    public var createdAt: Date = Date.distantPast
    /// EventKit identifier of the mirrored reminder (FR-DL-03), if any.
    public var mirroredReminderID: String?
    public var mirrorListID: String?
    /// Mark's per-item override allowing a college deadline to mirror to iCloud Reminders.
    public var mirrorOverride: Bool = false

    public init(
        deadlineUUID: UUID = UUID(),
        title: String,
        dueAt: Date,
        isAllDay: Bool = false,
        origin: DeadlineOrigin = .manual,
        reminderOffsetsMinutes: [Int] = defaultDeadlineOffsetsMinutes,
        dataClass: DataClass,
        sourceID: SourceID? = nil,
        createdAt: Date
    ) {
        self.deadlineUUID = deadlineUUID
        self.title = title
        self.dueAt = dueAt
        self.isAllDay = isAllDay
        originRaw = origin.rawValue
        self.reminderOffsetsMinutes = reminderOffsetsMinutes
        dataClassRaw = dataClass.rawValue
        sourceUUID = sourceID?.rawValue
        self.createdAt = createdAt
    }

    /// Unknown raw values read as `college`, the most restrictive class.
    public var dataClass: DataClass { DataClass(rawValue: dataClassRaw) ?? .college }
    public var sourceID: SourceID? { sourceUUID.map { SourceID($0) } }
    public var origin: DeadlineOrigin { DeadlineOrigin(rawValue: originRaw) ?? .manual }
    /// Unknown raw values read as `open`, so a deadline is never silently lost.
    public var status: DeadlineStatus { DeadlineStatus(rawValue: statusRaw) ?? .open }

    public func markDone(at date: Date) {
        statusRaw = DeadlineStatus.done.rawValue
        completedAt = date
        snoozedUntil = nil
    }

    public func snooze(until date: Date) {
        snoozedUntil = date
    }

    /// Moves the due time and clears any snooze.
    public func reschedule(to date: Date) {
        dueAt = date
        snoozedUntil = nil
    }

    /// A value copy for planners and queries, which never touch the model.
    public var snapshot: DeadlineSnapshot {
        DeadlineSnapshot(
            id: deadlineUUID, title: title, dueAt: dueAt, isAllDay: isAllDay, origin: origin,
            reminderOffsetsMinutes: reminderOffsetsMinutes, dataClass: dataClass, status: status,
            snoozedUntil: snoozedUntil, mirrorOverride: mirrorOverride
        )
    }
}

/// A `Sendable` value copy of a ``Deadline``.
public struct DeadlineSnapshot: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let title: String
    public let dueAt: Date
    public let isAllDay: Bool
    public let origin: DeadlineOrigin
    public let reminderOffsetsMinutes: [Int]
    public let dataClass: DataClass
    public let status: DeadlineStatus
    public let snoozedUntil: Date?
    public let mirrorOverride: Bool

    public init(
        id: UUID = UUID(), title: String, dueAt: Date, isAllDay: Bool = false, origin: DeadlineOrigin = .manual,
        reminderOffsetsMinutes: [Int] = defaultDeadlineOffsetsMinutes, dataClass: DataClass,
        status: DeadlineStatus = .open, snoozedUntil: Date? = nil, mirrorOverride: Bool = false
    ) {
        self.id = id
        self.title = title
        self.dueAt = dueAt
        self.isAllDay = isAllDay
        self.origin = origin
        self.reminderOffsetsMinutes = reminderOffsetsMinutes
        self.dataClass = dataClass
        self.status = status
        self.snoozedUntil = snoozedUntil
        self.mirrorOverride = mirrorOverride
    }
}

/// Queries over snapshots (FR-DL-04).
public enum DeadlineQueries {
    /// Open deadlines past due and not snoozed beyond `now`, oldest first.
    public static func overdue(_ snapshots: [DeadlineSnapshot], now: Date) -> [DeadlineSnapshot] {
        snapshots
            .filter { $0.status == .open && $0.dueAt < now && ($0.snoozedUntil ?? .distantPast) <= now }
            .sorted { $0.dueAt < $1.dueAt }
    }
}
