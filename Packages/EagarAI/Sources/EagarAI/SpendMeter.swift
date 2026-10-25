import EagarLedger
import Foundation

/// Cloud spend from the privacy ledger's recorded costs (FR-AI-09, skeleton).
public struct SpendMeter: Sendable {
    public struct Report: Sendable, Equatable {
        public var todayMicroUSD: Int64
        public var monthMicroUSD: Int64
        public var byPurposeMicroUSD: [String: Int64]
        public var byDayMicroUSD: [Date: Int64]
    }

    /// Soft monthly cap; reaching it pauses cloud features. `nil` means no cap.
    public var monthlyCapMicroUSD: Int64?
    public var calendar: Calendar

    public init(monthlyCapMicroUSD: Int64? = nil, calendar: Calendar = .current) {
        self.monthlyCapMicroUSD = monthlyCapMicroUSD
        self.calendar = calendar
    }

    public func report(_ records: [LedgerRecord], now: Date) -> Report {
        var report = Report(todayMicroUSD: 0, monthMicroUSD: 0, byPurposeMicroUSD: [:], byDayMicroUSD: [:])
        for record in records {
            guard let cost = record.costMicroUSD else { continue }
            let day = calendar.startOfDay(for: record.at)
            report.byDayMicroUSD[day, default: 0] += cost
            if calendar.isDate(record.at, equalTo: now, toGranularity: .month) {
                report.monthMicroUSD += cost
                report.byPurposeMicroUSD[record.purpose, default: 0] += cost
            }
            if calendar.isDate(record.at, inSameDayAs: now) {
                report.todayMicroUSD += cost
            }
        }
        return report
    }

    /// Whether cloud features should pause (fed into ``PolicySnapshot/cloudPaused``).
    public func isCapReached(_ records: [LedgerRecord], now: Date) -> Bool {
        guard let cap = monthlyCapMicroUSD else { return false }
        return report(records, now: now).monthMicroUSD >= cap
    }
}
