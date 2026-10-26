import EagarCore
import Foundation
import SwiftData

/// How often a subscription bills (FR-TRIAL-01).
public enum BillingPeriod: String, Codable, Sendable, CaseIterable {
    case weekly, monthly, quarterly, yearly

    /// The calendar step between two charges.
    public var step: (component: Calendar.Component, value: Int) {
        switch self {
        case .weekly: (.day, 7)
        case .monthly: (.month, 1)
        case .quarterly: (.month, 3)
        case .yearly: (.year, 1)
        }
    }

    /// Multiplier that turns one charge into its monthly equivalent (FR-TRIAL-06).
    /// Weekly uses 52 weeks over 12 months.
    public var monthlyFactor: Decimal {
        switch self {
        case .weekly: Decimal(52) / Decimal(12)
        case .monthly: 1
        case .quarterly: Decimal(1) / Decimal(3)
        case .yearly: Decimal(1) / Decimal(12)
        }
    }
}

/// Whether Mark still has the subscription. `cancelled` is set only when Mark confirms he
/// cancelled it (FR-TRIAL-05); opening the cancel page changes nothing.
public enum TrialStatus: String, Codable, Sendable, CaseIterable {
    case active, cancelled
}

/// The default safety margin between cancel-by and the renewal (FR-TRIAL-01).
public let defaultTrialSafetyMarginDays = 2
/// Default reminder days before cancel-by; 0 is the day itself (FR-TRIAL-02).
public let defaultTrialReminderDays = [7, 3, 1, 0]
/// The default currency for manual entry (FR-TRIAL-01).
public let defaultTrialCurrencyCode = "EUR"

/// A free trial or a paid subscription (FR-TRIAL-01). Personal by default.
///
/// CloudKit-compatible: every attribute defaulted or optional, no unique constraints, no
/// relationships. Logical uniqueness is enforced by ``TrialUpsert``, not the schema.
@Model
public final class Trial: Classified {
    public var trialUUID: UUID = UUID()
    public var service: String = ""
    public var price: Decimal = 0
    /// ISO 4217 code, e.g. `EUR`.
    public var currencyCode: String = defaultTrialCurrencyCode
    public var periodRaw: String = BillingPeriod.monthly.rawValue
    /// True while the first charge is still a trial end rather than a renewal.
    public var isTrial: Bool = true
    public var startedAt: Date?
    /// The next (or first) charge. Later charges follow every `period`.
    public var renewsAt: Date = Date.distantFuture
    public var cancelURLString: String?
    public var statusRaw: String = TrialStatus.active.rawValue
    public var safetyMarginDays: Int = defaultTrialSafetyMarginDays
    public var reminderDays: [Int] = defaultTrialReminderDays
    public var dataClassRaw: String = DataClass.personal.rawValue
    public var sourceUUID: UUID?
    public var createdAt: Date = Date.distantPast
    public var cancelledAt: Date?

    public init(
        trialUUID: UUID = UUID(),
        service: String,
        price: Decimal,
        currencyCode: String = defaultTrialCurrencyCode,
        period: BillingPeriod = .monthly,
        isTrial: Bool = true,
        startedAt: Date? = nil,
        renewsAt: Date,
        cancelURL: URL? = nil,
        safetyMarginDays: Int = defaultTrialSafetyMarginDays,
        reminderDays: [Int] = defaultTrialReminderDays,
        dataClass: DataClass = .personal,
        sourceID: SourceID? = nil,
        createdAt: Date
    ) {
        self.trialUUID = trialUUID
        self.service = service
        self.price = price
        self.currencyCode = currencyCode
        periodRaw = period.rawValue
        self.isTrial = isTrial
        self.startedAt = startedAt
        self.renewsAt = renewsAt
        cancelURLString = cancelURL?.absoluteString
        self.safetyMarginDays = safetyMarginDays
        self.reminderDays = reminderDays
        dataClassRaw = dataClass.rawValue
        sourceUUID = sourceID?.rawValue
        self.createdAt = createdAt
    }

    /// Unknown raw values read as `college`, the most restrictive class.
    public var dataClass: DataClass { DataClass(rawValue: dataClassRaw) ?? .college }
    public var sourceID: SourceID? { sourceUUID.map { SourceID($0) } }
    /// Unknown raw values read as `monthly`.
    public var period: BillingPeriod { BillingPeriod(rawValue: periodRaw) ?? .monthly }
    /// Unknown raw values read as `active`, so a subscription is never silently dropped.
    public var status: TrialStatus { TrialStatus(rawValue: statusRaw) ?? .active }
    public var cancelURL: URL? { cancelURLString.flatMap(URL.init(string:)) }

    /// Records Mark's confirmation that he cancelled (FR-TRIAL-05).
    public func confirmCancelled(at date: Date) {
        statusRaw = TrialStatus.cancelled.rawValue
        cancelledAt = date
    }

    /// Undoes a mistaken confirmation.
    public func reactivate() {
        statusRaw = TrialStatus.active.rawValue
        cancelledAt = nil
    }

    /// Copies every editable value from `snapshot`. Identity, class, source and creation
    /// time are kept.
    public func update(from snapshot: TrialSnapshot) {
        service = snapshot.service
        price = snapshot.price
        currencyCode = snapshot.currencyCode
        periodRaw = snapshot.period.rawValue
        isTrial = snapshot.isTrial
        startedAt = snapshot.startedAt
        renewsAt = snapshot.renewsAt
        cancelURLString = snapshot.cancelURL?.absoluteString
        safetyMarginDays = snapshot.safetyMarginDays
        reminderDays = snapshot.reminderDays
        statusRaw = snapshot.status.rawValue
        cancelledAt = snapshot.cancelledAt
    }

    /// A value copy for planners and summaries, which never touch the model.
    public var snapshot: TrialSnapshot {
        TrialSnapshot(
            id: trialUUID, service: service, price: price, currencyCode: currencyCode, period: period,
            isTrial: isTrial, startedAt: startedAt, renewsAt: renewsAt, cancelURL: cancelURL, status: status,
            safetyMarginDays: safetyMarginDays, reminderDays: reminderDays, dataClass: dataClass,
            cancelledAt: cancelledAt
        )
    }
}

/// A `Sendable` value copy of a ``Trial``.
public struct TrialSnapshot: Sendable, Hashable, Identifiable {
    public var id: UUID
    public var service: String
    public var price: Decimal
    public var currencyCode: String
    public var period: BillingPeriod
    public var isTrial: Bool
    public var startedAt: Date?
    public var renewsAt: Date
    public var cancelURL: URL?
    public var status: TrialStatus
    public var safetyMarginDays: Int
    public var reminderDays: [Int]
    public var dataClass: DataClass
    public var cancelledAt: Date?

    public init(
        id: UUID = UUID(), service: String, price: Decimal, currencyCode: String = defaultTrialCurrencyCode,
        period: BillingPeriod = .monthly, isTrial: Bool = true, startedAt: Date? = nil, renewsAt: Date,
        cancelURL: URL? = nil, status: TrialStatus = .active, safetyMarginDays: Int = defaultTrialSafetyMarginDays,
        reminderDays: [Int] = defaultTrialReminderDays, dataClass: DataClass = .personal, cancelledAt: Date? = nil
    ) {
        self.id = id
        self.service = service
        self.price = price
        self.currencyCode = currencyCode
        self.period = period
        self.isTrial = isTrial
        self.startedAt = startedAt
        self.renewsAt = renewsAt
        self.cancelURL = cancelURL
        self.status = status
        self.safetyMarginDays = safetyMarginDays
        self.reminderDays = reminderDays
        self.dataClass = dataClass
        self.cancelledAt = cancelledAt
    }
}
