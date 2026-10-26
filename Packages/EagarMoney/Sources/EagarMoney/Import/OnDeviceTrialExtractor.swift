import EagarAI
import EagarCore
import Foundation

/// Extracts a trial from recognised text with the on-device model, **only** through
/// ``AIRouter`` (BD-06, invariant 2).
///
/// The request pins the on-device tier with `requiresPreferredTier`, so the router never falls
/// back to the Mac, Apple PCC or Claude even where policy would allow them for personal data;
/// if the on-device model is unavailable the call fails and the caller uses the parser. The
/// recognised text is sent as a personal `rawBody` payload.
///
/// Model output is never trusted on its own: each field is kept only if it can be found in
/// the recognised text (see ``validated(_:against:parser:)``).
public struct OnDeviceTrialExtractor: Sendable {
    public let router: AIRouter
    /// The source the import is attributed to, if the app registers one for policy.
    public let sourceID: SourceID?

    public init(router: AIRouter, sourceID: SourceID? = nil) {
        self.router = router
        self.sourceID = sourceID
    }

    static let instruction = """
    You read text recognised from a receipt or a screenshot about a subscription or free trial. \
    Reply with one JSON object and nothing else, with these keys: \
    "service" (the product or company name), "price" (the recurring charge, digits with a dot, no symbol), \
    "currency" (ISO 4217 code such as EUR, GBP or USD), "date" (the renewal or trial end date as YYYY-MM-DD), \
    "period" (weekly, monthly, quarterly or yearly). Use null for anything the text does not state. \
    Never guess or invent a value.
    """

    static let schema = JSONSchema(
        name: "trial_extraction",
        json: Data("""
        {"type":"object","additionalProperties":false,"required":["service","price","currency","date","period"],\
        "properties":{"service":{"type":["string","null"]},"price":{"type":["string","null"]},\
        "currency":{"type":["string","null"]},"date":{"type":["string","null"]},\
        "period":{"type":["string","null"],"enum":["weekly","monthly","quarterly","yearly",null]}}}
        """.utf8),
        dataClass: .publicContent
    )

    /// The exact request sent to the router for `text`.
    func request(for text: String) -> AIRequest {
        AIRequest(
            purpose: .extraction,
            inputs: [ClassifiedPayload(text, dataClass: .personal, sourceID: sourceID, kind: .rawBody)],
            system: ClassifiedPayload(Self.instruction, dataClass: .publicContent),
            outputSchema: Self.schema,
            preferredTier: .onDevice,
            requiresPreferredTier: true,
            maxOutputTokens: 200
        )
    }

    /// The model's raw answer, decoded but not yet validated.
    public struct Answer: Decodable, Sendable, Equatable {
        public var service: String?
        public var price: String?
        public var currency: String?
        public var date: String?
        public var period: String?
    }

    /// Runs the model. Throws the router's error (halted, no permitted provider, …) so the
    /// caller can fall back.
    public func answer(for lines: [String]) async throws(AIError) -> Answer? {
        let response = try await router.run(request(for: lines.joined(separator: "\n")))
        guard response.stopReason != .refusal else { return nil }
        return Self.decode(response.text)
    }

    /// Decodes the first JSON object in `text`, tolerating prose or code fences around it.
    static func decode(_ text: String) -> Answer? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return try? JSONDecoder().decode(Answer.self, from: Data(text[start ... end].utf8))
    }

    /// Keeps only the fields that are grounded in the recognised text: a price whose digits
    /// appear in it, a date the parser also finds in it, a service named in it, a known
    /// currency code. Models invent plausible values; those are dropped, not shown to Mark.
    static func validated(_ answer: Answer, against lines: [String], parser: ReceiptParser) -> TrialDraft {
        let text = lines.joined(separator: "\n")
        let lower = text.lowercased()
        var draft = TrialDraft(isTrial: lower.contains("trial"))

        if let service = answer.service?.trimmingCharacters(in: .whitespacesAndNewlines), !service.isEmpty,
           lower.contains(service.lowercased()) || parser.merchants.contains(where: { $0.name == service && $0.aliases.contains(where: { ReceiptParser.containsWord($0, in: lower) }) }) {
            draft.service = service
        }
        if let raw = answer.price, let price = ReceiptParser.decimal(from: raw),
           parser.prices(in: lines).contains(where: { $0.amount == price }) {
            draft.price = price
        }
        if let code = answer.currency?.uppercased(), ["EUR", "GBP", "USD", "CAD", "AUD"].contains(code) {
            draft.currencyCode = code
        }
        if let raw = answer.date, let date = isoDay(raw, calendar: parser.calendar),
           parser.dates(in: lines, currencyHint: draft.currencyCode).contains(where: { $0.date == date }) {
            draft.renewsAt = date
        }
        draft.period = answer.period.flatMap(BillingPeriod.init(rawValue:))
        return draft
    }

    static func isoDay(_ raw: String, calendar: Calendar) -> Date? {
        let parts = raw.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else { return nil }
        return calendar.startOfDay(for: date)
    }
}
