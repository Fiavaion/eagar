import EagarCalendar
import EagarCore
import EagarFeeds
import Foundation

/// Loan deadlines and return reminders (FR-BOOK-03, FR-DL-01 origin `booking`).
///
/// A loan becomes an M1 ``Deadline`` whose reminder offsets are the return reminders, so the
/// existing deadline notification sync schedules them. College deadlines are content-free in
/// notifications ("A college deadline is due in 2 hours", BD-04), exactly as in M1.
public enum LoanReminders {
    /// 24 hours and 2 hours before the due time (FR-BOOK-03).
    public static let defaultOffsetsMinutes = [1440, 120]

    /// The deadline for a booking: active loans give an open deadline; closed loans give a
    /// closed one (so an existing deadline is marked done); anything else gives none.
    public static func deadline(for record: BookingRecord, source: SourceID, offsetsMinutes: [Int] = defaultOffsetsMinutes) -> FeedDeadline? {
        guard record.kind == .equipment, let due = record.due, record.isActiveLoan || record.isClosed else { return nil }
        return FeedDeadline(
            origin: .booking, sourceID: source, externalID: record.id, title: record.title, dueAt: due, isAllDay: false,
            itemClass: .college, reminderOffsetsMinutes: offsetsMinutes, isClosed: record.isClosed
        )
    }

    /// The return reminders for `loans`, as the M1 planner would schedule them from the
    /// persisted deadlines. Identifiers match (`deadline.<uuid>.<offset>`), so using both never
    /// schedules a reminder twice.
    public static func plan(
        _ loans: [BookingSnapshot], offsetsMinutes: [Int] = defaultOffsetsMinutes, now: Date, calendar: Calendar = .current
    ) -> [PlannedNotification] {
        let snapshots = loans.compactMap { loan -> DeadlineSnapshot? in
            guard loan.booking.isActiveLoan, let source = loan.sourceID else { return nil }
            return deadline(for: loan.booking, source: source, offsetsMinutes: offsetsMinutes)?.snapshot
        }
        return DeadlineNotificationPlan.plan(snapshots, now: now, calendar: calendar)
    }
}
