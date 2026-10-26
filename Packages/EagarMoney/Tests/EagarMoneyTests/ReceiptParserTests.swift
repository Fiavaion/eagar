import Foundation
import Testing
@testable import EagarMoney

struct ReceiptParserTests {
    let cal = TestCalendars.dublin
    var parser: ReceiptParser { ReceiptParser(calendar: cal) }

    @Test(arguments: [
        ("9.99", "9.99"), ("2,99", "2.99"), ("1,234.56", "1234.56"), ("1.234,56", "1234.56"),
        ("96", "96"), ("96.00", "96"), ("1,234", "1234"), ("0.5", "0.5"),
    ])
    func decimals(raw: String, expected: String) {
        #expect(ReceiptParser.decimal(from: raw) == Decimal(string: expected))
    }

    @Test func pricesWithSymbolsAndCodes() {
        let lines = ["€9.99", "£10.99/month", "$13.99/mo", "US$ 59.99", "EUR 12.99", "2,99 €", "15.00 GBP", "C$4.99", "23% off"]
        let prices = parser.prices(in: lines)
        #expect(prices.map(\.currencyCode) == ["EUR", "GBP", "USD", "USD", "EUR", "EUR", "GBP", "CAD"])
        #expect(prices.map(\.amount) == ["9.99", "10.99", "13.99", "59.99", "12.99", "2.99", "15.00", "4.99"].map { Decimal(string: $0)! })
    }

    @Test func totalBeatsVATAndSubtotalAndZero() {
        let lines = ["Free for 7 days: £0.00", "Subtotal €56.90", "VAT €13.09", "Total €69.99"]
        #expect(parser.parse(lines: lines).price == Decimal(string: "69.99"))
    }

    @Test(arguments: [
        ("Renews 3 Dec 2026", "2026-12-03"), ("Renews 3rd December 2026", "2026-12-03"),
        ("renews December 3, 2026", "2026-12-03"), ("renews Sept 3 2026", "2026-09-03"),
        ("Trial ends 2026-12-03", "2026-12-03"), ("Renews 03.12.2026", "2026-12-03"),
        ("Renews 03/12/2026", "2026-12-03"), ("Renews 3/12/26", "2026-12-03"), ("Renews 25/12/2026", "2026-12-25"),
    ])
    func datesDayFirstByDefault(line: String, expected: String) throws {
        let date = try #require(parser.parse(lines: [line]).renewsAt)
        #expect(ReceiptFixture.dayString(date, cal) == expected)
    }

    @Test func ambiguousNumericDatesReadMonthFirstWithDollars() throws {
        let draft = parser.parse(lines: ["$5.00 / month", "Renews on 03/12/2026"])
        #expect(ReceiptFixture.dayString(try #require(draft.renewsAt), cal) == "2026-03-12")
        let unambiguous = parser.parse(lines: ["$5.00 / month", "Renews on 11/21/2026"])
        #expect(ReceiptFixture.dayString(try #require(unambiguous.renewsAt), cal) == "2026-11-21")
    }

    @Test func invalidDatesAreIgnored() {
        #expect(parser.parse(lines: ["Renews 31/02/2026", "Renews 30 Feb 2026", "1999-01-01"]).renewsAt == nil)
    }

    @Test func renewalBeatsPurchaseDate() throws {
        let draft = parser.parse(lines: ["Date: 26 Oct 2026", "Order date 25 Oct 2026", "Renews 3 Dec 2026"])
        #expect(ReceiptFixture.dayString(try #require(draft.renewsAt), cal) == "2026-12-03")
    }

    @Test func servicePrefersKnownMerchantsAndSkipsGenericHeaders() {
        #expect(parser.parse(lines: ["Receipt", "Apple Account", "Apple TV+", "€8.99"]).service == "Apple TV+")
        #expect(parser.parse(lines: ["Receipt", "Order 123", "Glasshouse Yoga", "€20"]).service == "Glasshouse Yoga")
        #expect(parser.parse(lines: ["Something about disneyland"]).service == "Something about disneyland")
        #expect(parser.parse(lines: ["Your Disney+ trial"]).service == "Disney+")
    }

    @Test func periodAndTrialFlag() {
        #expect(parser.parse(lines: ["€96.00/year"]).period == .yearly)
        #expect(parser.parse(lines: ["£8.99 a month"]).period == .monthly)
        #expect(parser.parse(lines: ["$2 per week"]).period == .weekly)
        #expect(parser.parse(lines: ["Free trial", "€5"]).isTrial)
        #expect(!parser.parse(lines: ["Receipt", "€5"]).isTrial)
    }

    /// The parser alone on the fixtures' ground-truth text (no OCR noise).
    @Test func parserScoresOnFixtureText() {
        let correct = ReceiptFixture.all.filter { $0.matches(parser.parse(lines: $0.lines), calendar: cal) }
        #expect(ReceiptFixture.all.count >= 10)
        #expect(correct.count == ReceiptFixture.all.count, "missed: \(Set(ReceiptFixture.all.map(\.file)).subtracting(correct.map(\.file)).sorted())")
    }

    @Test func currenciesOnFixtureText() {
        for fixture in ReceiptFixture.all {
            #expect(parser.parse(lines: fixture.lines).currencyCode == fixture.currency, "\(fixture.file)")
        }
    }

    // MARK: - Drafts (intent and share-extension surface)

    @Test func draftConfirmsWithDefaults() throws {
        let draft = TrialDraft(service: " Netflix ", renewsAt: TestCalendars.date(2026, 11, 1))
        let snapshot = try #require(draft.confirmed())
        #expect(snapshot.service == "Netflix")
        #expect(snapshot.price == 0 && snapshot.currencyCode == "EUR" && snapshot.period == .monthly)
        #expect(snapshot.dataClass == .personal)
        #expect(TrialDraft(service: "x").confirmed() == nil)
        #expect(TrialDraft(service: "  ", renewsAt: .now).confirmed() == nil)
        #expect(!draft.hasCoreFields)
    }
}
