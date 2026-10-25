import Foundation

/// Field-level last-writer-wins merge for a conflicting record (PRD §7.5).
///
/// `base` is the last version both sides agreed on. For each field: if only one side changed
/// it, that side wins; if both changed it to different values, the later edit wins (local edit
/// time against the server record's modification time); if neither changed it, it stays.
public enum ThreeWayMerge {
    public enum Winner: Sendable, Equatable { case local, server }

    public static func merge(
        base: SyncFields, local: SyncFields, server: SyncFields,
        localEditedAt: Date, serverModifiedAt: Date?
    ) -> SyncFields {
        var merged: SyncFields = [:]
        let names = Set(base.keys).union(local.keys).union(server.keys)
        let laterSide: Winner = (serverModifiedAt.map { $0 > localEditedAt } ?? false) ? .server : .local
        for name in names {
            let b = base[name] ?? .null
            let l = local[name] ?? .null
            let s = server[name] ?? .null
            let localChanged = l != b
            let serverChanged = s != b
            switch (localChanged, serverChanged) {
            case (false, false): merged[name] = b
            case (true, false): merged[name] = l
            case (false, true): merged[name] = s
            case (true, true): merged[name] = l == s ? l : (laterSide == .local ? l : s)
            }
        }
        return merged
    }

    /// The fields whose value differs between `old` and `new`.
    public static func changedFields(from old: SyncFields, to new: SyncFields) -> Set<String> {
        Set(old.keys).union(new.keys).filter { (old[$0] ?? .null) != (new[$0] ?? .null) }
    }
}
