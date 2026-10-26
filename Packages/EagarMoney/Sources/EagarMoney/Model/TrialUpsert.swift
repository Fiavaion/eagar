import Foundation
import SwiftData

/// Logical uniqueness for trials, which the CloudKit-compatible schema cannot enforce.
///
/// A trial is the same record when it has the same UUID, or, failing that, when an active
/// trial for the same service (case- and whitespace-insensitive) renews on the same calendar
/// day. That second rule stops a re-imported receipt or a share-sheet repeat from creating a
/// duplicate.
public enum TrialUpsert {
    /// Updates the matching trial from `snapshot`, or inserts a new one. Returns the stored
    /// model. A logical match keeps its own UUID, class and creation time. The caller saves.
    @discardableResult
    public static func upsert(_ snapshot: TrialSnapshot, in context: ModelContext, now: Date, calendar: Calendar = .current) throws -> Trial {
        if let existing = try find(id: snapshot.id, in: context) ?? findLogical(snapshot, in: context, calendar: calendar) {
            existing.update(from: snapshot)
            return existing
        }
        let trial = Trial(
            trialUUID: snapshot.id, service: snapshot.service, price: snapshot.price, currencyCode: snapshot.currencyCode,
            period: snapshot.period, isTrial: snapshot.isTrial, startedAt: snapshot.startedAt, renewsAt: snapshot.renewsAt,
            cancelURL: snapshot.cancelURL, safetyMarginDays: snapshot.safetyMarginDays, reminderDays: snapshot.reminderDays,
            dataClass: snapshot.dataClass, createdAt: now
        )
        trial.update(from: snapshot)
        context.insert(trial)
        return trial
    }

    /// The trial with this UUID, if any.
    public static func find(id: UUID, in context: ModelContext) throws -> Trial? {
        var descriptor = FetchDescriptor<Trial>(predicate: #Predicate { $0.trialUUID == id })
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    /// An active trial for the same service renewing on the same day.
    static func findLogical(_ snapshot: TrialSnapshot, in context: ModelContext, calendar: Calendar) throws -> Trial? {
        let key = normalised(snapshot.service)
        guard !key.isEmpty else { return nil }
        let active = TrialStatus.active.rawValue
        let candidates = try context.fetch(FetchDescriptor<Trial>(predicate: #Predicate { $0.statusRaw == active }))
        return candidates.first {
            normalised($0.service) == key && calendar.isDate($0.renewsAt, inSameDayAs: snapshot.renewsAt)
        }
    }

    static func normalised(_ service: String) -> String {
        service.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
