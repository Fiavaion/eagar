import EagarCalendar
import EagarCore
import Foundation

/// Maps a trial's cancel-by date to an EagarCalendar deadline with origin `trial` (FR-DL-01).
///
/// The deadline reuses the trial's UUID, so re-mapping after an edit updates the same
/// deadline. It carries **no reminder offsets**: trial reminders come from
/// ``TrialReminderPlan`` (7/3/1/0 days, FR-TRIAL-02), and offsets here would notify twice.
public enum TrialDeadlineMapping {
    /// The deadline for the trial's current cancel-by: open while active, done once Mark has
    /// confirmed the cancellation. `nil` when an active trial has no future cancel-by.
    public static func snapshot(for trial: TrialSnapshot, now: Date, calendar: Calendar = .current) -> DeadlineSnapshot? {
        let cancelBy: Date
        let status: DeadlineStatus
        switch trial.status {
        case .active:
            guard let target = trial.nextCancelBy(now: now, calendar: calendar) else { return nil }
            cancelBy = target.cancelBy
            status = .open
        case .cancelled:
            cancelBy = trial.cancelBy(calendar: calendar)
            status = .done
        }
        return DeadlineSnapshot(
            id: trial.id,
            title: title(for: trial),
            dueAt: calendar.startOfDay(for: cancelBy),
            isAllDay: true,
            origin: .trial,
            reminderOffsetsMinutes: [],
            dataClass: trial.dataClass,
            status: status
        )
    }

    /// A new `Deadline` model for the trial, or `nil` as for ``snapshot(for:now:calendar:)``.
    public static func makeDeadline(for trial: TrialSnapshot, now: Date, calendar: Calendar = .current, createdAt: Date) -> Deadline? {
        guard let snapshot = snapshot(for: trial, now: now, calendar: calendar) else { return nil }
        let deadline = Deadline(
            deadlineUUID: snapshot.id, title: snapshot.title, dueAt: snapshot.dueAt, isAllDay: true,
            origin: .trial, reminderOffsetsMinutes: [], dataClass: snapshot.dataClass, createdAt: createdAt
        )
        if snapshot.status == .done { deadline.markDone(at: trial.cancelledAt ?? now) }
        return deadline
    }

    static func title(for trial: TrialSnapshot) -> String {
        String(localized: "Cancel \(trial.service)", bundle: .module)
    }
}
