import EagarCore
import Foundation

/// A trial Mark has not confirmed yet: what the "Add trial" intent, the share extension and
/// screenshot import produce (FR-TRIAL-01, FR-TRIAL-03, FR-OS-03). Every field is optional
/// because extraction can miss any of them; the confirmation screen fills the gaps.
public struct TrialDraft: Sendable, Hashable {
    public var service: String?
    public var price: Decimal?
    /// ISO 4217 code, e.g. `EUR`.
    public var currencyCode: String?
    /// The renewal or trial-end date.
    public var renewsAt: Date?
    public var period: BillingPeriod?
    public var isTrial: Bool
    public var cancelURL: URL?

    public init(
        service: String? = nil, price: Decimal? = nil, currencyCode: String? = nil, renewsAt: Date? = nil,
        period: BillingPeriod? = nil, isTrial: Bool = true, cancelURL: URL? = nil
    ) {
        self.service = service
        self.price = price
        self.currencyCode = currencyCode
        self.renewsAt = renewsAt
        self.period = period
        self.isTrial = isTrial
        self.cancelURL = cancelURL
    }

    /// Whether the three fields the import acceptance criterion checks (service, price,
    /// date) are present.
    public var hasCoreFields: Bool { service?.isEmpty == false && price != nil && renewsAt != nil }

    /// The confirmed trial, once Mark accepts the draft. Needs at least a service and a
    /// renewal date; price defaults to 0, currency to EUR and period to monthly. Imports are
    /// personal (a screenshot or shared text is Mark's own data).
    public func confirmed(id: UUID = UUID(), dataClass: DataClass = .personal) -> TrialSnapshot? {
        guard let service = service?.trimmingCharacters(in: .whitespacesAndNewlines), !service.isEmpty,
              let renewsAt
        else { return nil }
        return TrialSnapshot(
            id: id, service: service, price: price ?? 0, currencyCode: currencyCode ?? defaultTrialCurrencyCode,
            period: period ?? .monthly, isTrial: isTrial, renewsAt: renewsAt, cancelURL: cancelURL, dataClass: dataClass
        )
    }
}
