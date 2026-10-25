import EagarCore
import Foundation

/// Which reminder lists a deadline may be mirrored to (FR-DL-03).
public enum ReminderMirrorPolicy {
    /// Personal deadlines: any modifiable reminder list. College deadlines: only lists in
    /// `collegeListIDs` or on a local account, never iCloud unless the item's override is set
    /// (an overridden item may use any iCloud list).
    public static func eligibleLists(
        for deadline: DeadlineSnapshot, among lists: [CalendarInfo], collegeListIDs: Set<String>
    ) -> [CalendarInfo] {
        lists.filter { list in
            guard list.entity == .reminder, list.allowsModification else { return false }
            guard deadline.dataClass == .college else { return true }
            if list.sourceKind == .iCloud { return deadline.mirrorOverride }
            return list.sourceKind == .local || collegeListIDs.contains(list.id)
        }
    }
}

public enum ReminderMirror {
    /// Saves a reminder for `deadline` in `list` after checking the policy. The reminder title
    /// is the deadline title, which is allowed because eligible college lists are college or
    /// local. Throws `CalendarError.crossBoundaryWrite` for an ineligible list. Returns the
    /// reminder identifier.
    public static func mirror(
        _ deadline: DeadlineSnapshot, to list: CalendarInfo, collegeListIDs: Set<String> = [], store: some EventStoreAdapting
    ) async throws(CalendarError) -> String {
        guard !ReminderMirrorPolicy.eligibleLists(for: deadline, among: [list], collegeListIDs: collegeListIDs).isEmpty else {
            throw .crossBoundaryWrite
        }
        return try await store.saveReminder(ReminderDraft(title: deadline.title, due: deadline.dueAt), toList: list.id)
    }
}
