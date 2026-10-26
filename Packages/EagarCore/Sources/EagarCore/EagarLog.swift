import Foundation
import os
import Synchronization

/// Subsystems that log. One `os.Logger` category each.
public enum LogCategory: String, Sendable, CaseIterable {
    case app, ai, store, ledger, security, rules, money, people
}

/// Severity, mirroring `OSLogType`.
public enum LogLevel: String, Sendable, Comparable, CaseIterable {
    case debug, info, notice, error, fault

    private var rank: Int { Self.allCases.firstIndex(of: self)! }
    public static func < (lhs: LogLevel, rhs: LogLevel) -> Bool { lhs.rank < rhs.rank }
}

/// One emitted log line, as delivered to sinks.
public struct LogRecord: Sendable {
    public let category: LogCategory
    public let level: LogLevel
    public let text: String
}

/// Receives every log line in addition to `os.Logger`. Used by log-capture tests.
public protocol LogSink: Sendable {
    func receive(_ record: LogRecord)
}

/// The only logging API in Eagar (BD-25). Wraps `os.Logger`; accepts only ``LogMessage``.
///
/// Because a `LogMessage` contains only literals and `LogSafe` values, it is logged with
/// public privacy so it stays readable in Console.
public struct EagarLog: Sendable {
    public let category: LogCategory
    private let logger: Logger

    private static let subsystem = Bundle.main.bundleIdentifier ?? "eagar"
    private static let sinks = Mutex<[ObjectIdentifier: any LogSink]>([:])

    public init(_ category: LogCategory) {
        self.category = category
        logger = Logger(subsystem: Self.subsystem, category: category.rawValue)
    }

    public func debug(_ message: LogMessage) { emit(.debug, message) }
    public func info(_ message: LogMessage) { emit(.info, message) }
    public func notice(_ message: LogMessage) { emit(.notice, message) }
    public func error(_ message: LogMessage) { emit(.error, message) }
    public func fault(_ message: LogMessage) { emit(.fault, message) }

    private func emit(_ level: LogLevel, _ message: LogMessage) {
        let text = message.text
        switch level {
        case .debug: logger.debug("\(text, privacy: .public)")
        case .info: logger.info("\(text, privacy: .public)")
        case .notice: logger.notice("\(text, privacy: .public)")
        case .error: logger.error("\(text, privacy: .public)")
        case .fault: logger.fault("\(text, privacy: .public)")
        }
        let record = LogRecord(category: category, level: level, text: text)
        for sink in Self.sinks.withLock({ Array($0.values) }) {
            sink.receive(record)
        }
    }

    /// Registers a sink. Returns a token; pass it to ``removeSink(_:)`` when done.
    public static func addSink(_ sink: some LogSink & AnyObject) -> ObjectIdentifier {
        let id = ObjectIdentifier(sink)
        sinks.withLock { $0[id] = sink }
        return id
    }

    public static func removeSink(_ id: ObjectIdentifier) {
        _ = sinks.withLock { $0.removeValue(forKey: id) }
    }
}
