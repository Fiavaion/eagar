import Foundation

/// A price found in text.
public struct ParsedPrice: Sendable, Hashable {
    public let amount: Decimal
    /// ISO 4217 code.
    public let currencyCode: String
    /// Index of the line it was found on.
    public let line: Int
}

/// A date found in text, at the start of its day in the parser's calendar.
public struct ParsedDate: Sendable, Hashable {
    public let date: Date
    public let line: Int
}

/// The deterministic receipt and screenshot parser (FR-TRIAL-03): regular expressions and
/// keyword scores, no model. It is the fallback whenever the on-device model is unavailable,
/// halted or wrong, and the cross-check for what the model returns.
///
/// It reads prices with `€ £ $ US$` or `EUR GBP USD` before or after the amount (decimal
/// point or comma), dates as `3 Dec 2026`, `December 3, 2026`, `2026-12-03`, `03/12/2026`
/// and `03.12.2026`, and the service from ``KnownMerchant`` or the first plausible header.
public struct ReceiptParser: Sendable {
    public let calendar: Calendar
    public let merchants: [KnownMerchant]

    public init(calendar: Calendar = .current, merchants: [KnownMerchant] = KnownMerchant.builtIn) {
        self.calendar = calendar
        self.merchants = merchants
    }

    /// Extracts a draft from recognised lines, top to bottom.
    public func parse(lines rawLines: [String]) -> TrialDraft {
        let lines = rawLines.map(Self.normalise).filter { !$0.isEmpty }
        let price = bestPrice(in: lines)
        let currency = price?.currencyCode
        let date = bestDate(in: lines, currencyHint: currency)
        let text = lines.joined(separator: "\n").lowercased()
        return TrialDraft(
            service: service(in: lines),
            price: price?.amount,
            currencyCode: currency,
            renewsAt: date?.date,
            period: period(in: lines, priceLine: price?.line),
            isTrial: text.contains("trial")
        )
    }

    // MARK: - Normalising

    static func normalise(_ line: String) -> String {
        line.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Prices

    private static let amount = #"(\d{1,3}(?:[.,\x{2009} ]\d{3})*(?:[.,]\d{1,2})?|\d+(?:[.,]\d{1,2})?)"#
    private static let symbol = #"(US\$|C\$|A\$|€|£|\$|EUR|GBP|USD)"#
    private static let prefixed = try! NSRegularExpression(pattern: symbol + #"\s?"# + amount + #"(?![\d])"#, options: [.caseInsensitive])
    private static let suffixed = try! NSRegularExpression(pattern: #"(?<![\d.,])"# + amount + #"\s?"# + symbol + #"(?![A-Za-z])"#, options: [.caseInsensitive])

    /// Every price in `lines`, in reading order.
    public func prices(in lines: [String]) -> [ParsedPrice] {
        var found: [ParsedPrice] = []
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            var hits: [(location: Int, price: ParsedPrice)] = []
            for match in Self.prefixed.matches(in: line, range: range) {
                if let price = Self.price(symbol: line[match.range(at: 1)], amount: line[match.range(at: 2)], line: index) {
                    hits.append((match.range.location, price))
                }
            }
            for match in Self.suffixed.matches(in: line, range: range) {
                let overlaps = hits.contains { NSIntersectionRange(NSRange(location: $0.location, length: 1), match.range).length > 0 }
                if !overlaps, let price = Self.price(symbol: line[match.range(at: 2)], amount: line[match.range(at: 1)], line: index) {
                    hits.append((match.range.location, price))
                }
            }
            found += hits.sorted { $0.location < $1.location }.map(\.price)
        }
        return found
    }

    /// The charge: the price on the best-scoring line. Totals and per-period prices score
    /// up; VAT, tax, subtotals, discounts and zero amounts (a free trial's "£0.00") down.
    func bestPrice(in lines: [String]) -> ParsedPrice? {
        let candidates = prices(in: lines)
        return candidates.enumerated().max { lhs, rhs in
            let l = score(lhs.element, lines), r = score(rhs.element, lines)
            return l != r ? l < r : lhs.offset > rhs.offset // ties: the earlier one
        }?.element
    }

    private func score(_ price: ParsedPrice, _ lines: [String]) -> Int {
        let line = lines[price.line].lowercased()
        var score = 0
        if price.amount == 0 { score -= 10 }
        if Self.containsAny(line, ["vat", "tax", "subtotal", "sub-total", "discount", "saving", "credit", "refund"]) { score -= 5 }
        if line.contains("total") && !line.contains("subtotal") { score += 3 }
        if Self.containsAny(line, ["/month", "per month", "a month", "/mo", "monthly", "/year", "per year", "a year", "/yr",
                                   "annually", "yearly", "/week", "per week", "then", "after", "price", "renew", "billed"]) {
            score += 2
        }
        return score
    }

    private static func price(symbol: Substring, amount: Substring, line: Int) -> ParsedPrice? {
        guard let value = decimal(from: String(amount)), let code = currencyCode(for: symbol) else { return nil }
        return ParsedPrice(amount: value, currencyCode: code, line: line)
    }

    static func currencyCode(for symbol: some StringProtocol) -> String? {
        switch symbol.uppercased() {
        case "€", "EUR": "EUR"
        case "£", "GBP": "GBP"
        case "$", "US$", "USD": "USD"
        case "C$": "CAD"
        case "A$": "AUD"
        default: nil
        }
    }

    /// "1,234.56", "1.234,56", "2,99", "9.99", "96" → Decimal. The last separator followed by
    /// one or two digits is the decimal mark; other separators group thousands.
    static func decimal(from raw: String) -> Decimal? {
        let text = raw.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{2009}", with: "")
        var integer = text
        var fraction = ""
        if let mark = text.lastIndex(where: { $0 == "." || $0 == "," }) {
            let tail = text[text.index(after: mark)...]
            if (1 ... 2).contains(tail.count) {
                integer = String(text[..<mark])
                fraction = String(tail)
            }
        }
        integer.removeAll { $0 == "." || $0 == "," }
        guard !integer.isEmpty, integer.allSatisfy(\.isNumber), fraction.allSatisfy(\.isNumber) else { return nil }
        return Decimal(string: fraction.isEmpty ? integer : "\(integer).\(fraction)", locale: Locale(identifier: "en_US_POSIX"))
    }

    // MARK: - Dates

    private static let monthNames: [(String, Int)] = {
        var english = Calendar(identifier: .gregorian)
        english.locale = Locale(identifier: "en_GB")
        var names: [(String, Int)] = []
        for (index, name) in english.monthSymbols.enumerated() { names.append((name.lowercased(), index + 1)) }
        for (index, name) in english.shortMonthSymbols.enumerated() {
            names.append((name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")), index + 1))
        }
        names.append(("sept", 9))
        return names
    }()

    private static let monthPattern: String = {
        let names = monthNames.map(\.0).sorted { $0.count > $1.count }
        return "(" + names.joined(separator: "|") + ")"
    }()

    private static let dayMonthYear = try! NSRegularExpression(
        pattern: #"(?<!\d)(\d{1,2})(?:st|nd|rd|th)?\s+"# + monthPattern + #"\.?,?\s+(\d{4})"#, options: [.caseInsensitive])
    private static let monthDayYear = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])"# + monthPattern + #"\.?\s+(\d{1,2})(?:st|nd|rd|th)?,?\s+(\d{4})"#, options: [.caseInsensitive])
    private static let isoDate = try! NSRegularExpression(pattern: #"(?<!\d)(\d{4})-(\d{1,2})-(\d{1,2})(?!\d)"#)
    private static let numericDate = try! NSRegularExpression(pattern: #"(?<![\d.,])(\d{1,2})([/.\-])(\d{1,2})\2(\d{4}|\d{2})(?![\d])"#)

    /// Every date in `lines`. Ambiguous numeric dates (both parts ≤ 12) read day first,
    /// except with dollars, where they read month first; dotted dates always read day first.
    public func dates(in lines: [String], currencyHint: String? = nil) -> [ParsedDate] {
        var found: [ParsedDate] = []
        for (index, line) in lines.enumerated() {
            let range = NSRange(line.startIndex..., in: line)
            var hits: [(Int, Date)] = []
            for match in Self.dayMonthYear.matches(in: line, range: range) {
                if let date = make(year: line[match.range(at: 3)], month: Self.month(line[match.range(at: 2)]), day: line[match.range(at: 1)]) {
                    hits.append((match.range.location, date))
                }
            }
            for match in Self.monthDayYear.matches(in: line, range: range) {
                if let date = make(year: line[match.range(at: 3)], month: Self.month(line[match.range(at: 1)]), day: line[match.range(at: 2)]) {
                    hits.append((match.range.location, date))
                }
            }
            for match in Self.isoDate.matches(in: line, range: range) {
                if let date = make(year: line[match.range(at: 1)], month: Int(line[match.range(at: 2)]), day: line[match.range(at: 3)]) {
                    hits.append((match.range.location, date))
                }
            }
            for match in Self.numericDate.matches(in: line, range: range) {
                guard let first = Int(line[match.range(at: 1)]), let second = Int(line[match.range(at: 3)]) else { continue }
                let separator = line[match.range(at: 2)]
                let monthFirst: Bool
                if first > 12 { monthFirst = false }
                else if second > 12 { monthFirst = true }
                else { monthFirst = separator != "." && currencyHint == "USD" }
                var year = line[match.range(at: 4)]
                if year.count == 2 { year = "20" + year }
                let date = monthFirst
                    ? make(year: year, month: first, day: Substring(String(second)))
                    : make(year: year, month: second, day: Substring(String(first)))
                if let date { hits.append((match.range.location, date)) }
            }
            found += hits.sorted { $0.0 < $1.0 }.map { ParsedDate(date: $0.1, line: index) }
        }
        return found
    }

    /// The renewal or trial-end date: renewal, trial-end and billing wording scores up;
    /// purchase, order and invoice dates down. Ties go to the later date.
    func bestDate(in lines: [String], currencyHint: String?) -> ParsedDate? {
        dates(in: lines, currencyHint: currencyHint).max { lhs, rhs in
            let l = score(lhs, lines), r = score(rhs, lines)
            return l != r ? l < r : lhs.date < rhs.date
        }
    }

    private func score(_ date: ParsedDate, _ lines: [String]) -> Int {
        let line = lines[date.line].lowercased()
        var score = 0
        if Self.containsAny(line, ["renew", "ends", "end date", "ending", "billing", "billed on", "next payment", "next charge",
                                   "charged on", "will be charged", "starting", "starts", "expires", "until", "due"]) {
            score += 3
        }
        if Self.containsAny(line, ["purchase", "order", "invoice", "receipt", "issued", "started", "date:", "paid on", "signed up"]) {
            score -= 3
        }
        return score
    }

    private static func month(_ name: Substring) -> Int? {
        let key = name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return monthNames.first { $0.0 == key }?.1
    }

    private func make(year: Substring, month: Int?, day: Substring) -> Date? {
        guard let year = Int(year), let month, let day = Int(day),
              (1 ... 12).contains(month), (1 ... 31).contains(day), (2000 ... 2100).contains(year)
        else { return nil }
        let components = DateComponents(year: year, month: month, day: day)
        guard components.isValidDate(in: calendar), let date = calendar.date(from: components) else { return nil }
        return calendar.startOfDay(for: date)
    }

    // MARK: - Period and service

    func period(in lines: [String], priceLine: Int?) -> BillingPeriod? {
        let ordered = (priceLine.map { [lines[$0]] } ?? []) + lines
        for line in ordered.map({ $0.lowercased() }) {
            if Self.containsAny(line, ["/week", "per week", "a week", "weekly"]) { return .weekly }
            if Self.containsAny(line, ["quarter"]) { return .quarterly }
            if Self.containsAny(line, ["/year", "per year", "a year", "/yr", "yearly", "annual", "annually", "12 months"]) { return .yearly }
            if Self.containsAny(line, ["/month", "per month", "a month", "/mo", "monthly", "month"]) { return .monthly }
        }
        return nil
    }

    /// Lines that are never a service name on their own.
    private static let genericHeaders: Set<String> = [
        "receipt", "your receipt", "invoice", "tax invoice", "apple", "apple account", "app store", "order", "order summary",
        "subscription", "subscriptions", "subscription summary", "thank you", "thanks", "confirmation", "payment", "billing",
        "welcome", "membership", "membership confirmed", "your free trial is active",
    ]

    func service(in lines: [String]) -> String? {
        for line in lines {
            let lower = line.lowercased()
            let hits = merchants.flatMap { merchant in
                merchant.aliases.filter { Self.containsWord($0, in: lower) }.map { (merchant.name, $0.count) }
            }
            if let best = hits.max(by: { $0.1 < $1.1 }) { return best.0 }
        }
        return lines.first { line in
            let lower = line.lowercased()
            return (2 ... 40).contains(line.count) && line.contains(where: \.isLetter) && !line.contains(where: \.isNumber)
                && !line.contains("@") && !Self.genericHeaders.contains(lower)
        }
    }

    static func containsWord(_ word: String, in text: String) -> Bool {
        let pattern = #"(?<![\p{L}\p{N}])"# + NSRegularExpression.escapedPattern(for: word) + #"(?![\p{L}\p{N}])"#
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    private static func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

private extension String {
    subscript(range: NSRange) -> Substring {
        guard let swiftRange = Range(range, in: self) else { return "" }
        return self[swiftRange]
    }
}
