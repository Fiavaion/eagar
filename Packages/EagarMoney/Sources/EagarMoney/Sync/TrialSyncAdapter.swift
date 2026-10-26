import EagarCore
import EagarSync
import Foundation
import SwiftData

/// Syncs personal trials and subscriptions through PersonalStore's CloudKit zone (BD-02).
/// A college-class trial would live in CollegeStore, which the sync layer never scans.
///
/// The price travels as a locale-independent decimal string ("9.99"), because CloudKit has no
/// decimal type and a `Double` would lose cents.
public struct TrialSyncAdapter: SyncAdapter {
    public let recordType = "Trial"
    public let fieldKinds: [String: SyncFieldKind] = [
        "service": .string, "price": .string, "currency": .string, "period": .string, "isTrial": .bool,
        "startedAt": .date, "renewsAt": .date, "cancelURL": .string, "status": .string, "marginDays": .int,
        "reminderDays": .ints, "source": .string, "createdAt": .date, "cancelledAt": .date,
    ]
    public let encryptedFieldNames: Set<String> = []

    public init() {}

    public func recordName(of model: Trial) -> String { model.trialUUID.uuidString }

    public func fields(of model: Trial) -> SyncFields {
        [
            "service": .string(model.service),
            "price": .string(Self.encode(model.price)),
            "currency": .string(model.currencyCode),
            "period": .string(model.periodRaw),
            "isTrial": .bool(model.isTrial),
            "startedAt": model.startedAt.map(SyncValue.date) ?? .null,
            "renewsAt": .date(model.renewsAt),
            "cancelURL": model.cancelURLString.map(SyncValue.string) ?? .null,
            "status": .string(model.statusRaw),
            "marginDays": .int(Int64(model.safetyMarginDays)),
            "reminderDays": .ints(model.reminderDays.map(Int64.init)),
            "source": model.sourceUUID.map { .string($0.uuidString) } ?? .null,
            "createdAt": .date(model.createdAt),
            "cancelledAt": model.cancelledAt.map(SyncValue.date) ?? .null,
        ]
    }

    public func all(in context: ModelContext) throws -> [Trial] {
        try context.fetch(FetchDescriptor<Trial>())
    }

    public func find(recordName: String, in context: ModelContext) throws -> Trial? {
        guard let uuid = UUID(uuidString: recordName) else { return nil }
        return try TrialUpsert.find(id: uuid, in: context)
    }

    public func make(recordName: String, fields: SyncFields, dataClass: DataClass) -> Trial {
        let trial = Trial(
            trialUUID: UUID(uuidString: recordName) ?? UUID(), service: "", price: 0, renewsAt: .distantFuture,
            dataClass: dataClass, createdAt: .distantPast
        )
        apply(fields, to: trial)
        return trial
    }

    public func apply(_ fields: SyncFields, to model: Trial) {
        for (name, value) in fields {
            switch (name, value) {
            case let ("service", .string(v)): model.service = v
            case let ("price", .string(v)): if let price = Self.decode(v) { model.price = price }
            case let ("currency", .string(v)): model.currencyCode = v
            case let ("period", .string(v)): model.periodRaw = v
            case let ("isTrial", .bool(v)): model.isTrial = v
            case let ("startedAt", .date(v)): model.startedAt = v
            case ("startedAt", .null): model.startedAt = nil
            case let ("renewsAt", .date(v)): model.renewsAt = v
            case let ("cancelURL", .string(v)): model.cancelURLString = v
            case ("cancelURL", .null): model.cancelURLString = nil
            case let ("status", .string(v)): model.statusRaw = v
            case let ("marginDays", .int(v)): model.safetyMarginDays = Int(v)
            case let ("reminderDays", .ints(v)): model.reminderDays = v.map { Int($0) }
            case let ("source", .string(v)): model.sourceUUID = UUID(uuidString: v)
            case ("source", .null): model.sourceUUID = nil
            case let ("createdAt", .date(v)): model.createdAt = v
            case let ("cancelledAt", .date(v)): model.cancelledAt = v
            case ("cancelledAt", .null): model.cancelledAt = nil
            default: break
            }
        }
    }

    private static let posix = Locale(identifier: "en_US_POSIX")

    static func encode(_ price: Decimal) -> String {
        NSDecimalNumber(decimal: price).description(withLocale: posix)
    }

    static func decode(_ text: String) -> Decimal? {
        Decimal(string: text, locale: posix)
    }
}
