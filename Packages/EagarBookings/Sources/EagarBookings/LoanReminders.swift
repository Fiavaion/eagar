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

    /// The ID of a loan's accepted return reminder (FR-BOOK-04): one per loan, so accepting a
    /// new slot moves it instead of adding a second. It has origin `booking` and the loan's
    /// source, so it is deleted with the loan, on close and on disconnect.
    public static func returnReminderID(source: SourceID, bookingID: String) -> UUID {
        FeedDeadline.deadlineID(origin: .booking, sourceID: source, externalID: "return:\(bookingID)")
    }

    /// The return reminder for an accepted earlier slot: a college deadline at the slot's
    /// start, reminding 15 minutes before and at the time.
    public static func returnReminder(bookingID: String, title: String, source: SourceID, at start: Date) -> FeedDeadline {
        FeedDeadline(
            origin: .booking, sourceID: source, externalID: "return:\(bookingID)", title: title, dueAt: start, isAllDay: false,
            itemClass: .college, reminderOffsetsMinutes: [15, 0]
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
