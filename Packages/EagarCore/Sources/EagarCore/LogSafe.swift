import Foundation

/// A value that may appear in logs in clear text (BD-25, invariant 7).
///
/// Conform only types that can never carry content or secrets: enums, counts, durations,
/// opaque IDs. `String` deliberately does not conform; a message body, subject, address,
/// name, key or profile line can therefore never be interpolated into an ``EagarLog`` message.
public protocol LogSafe: Sendable {
    var logDescription: String { get }
}

extension Int: LogSafe { public var logDescription: String { String(self) } }
extension Int64: LogSafe { public var logDescription: String { String(self) } }
extension UInt: LogSafe { public var logDescription: String { String(self) } }
extension Double: LogSafe { public var logDescription: String { String(self) } }
extension Bool: LogSafe { public var logDescription: String { String(self) } }
extension Duration: LogSafe { public var logDescription: String { formatted(.units(allowed: [.seconds, .milliseconds])) } }
extension DataClass: LogSafe { public var logDescription: String { rawValue } }

/// A log message built only from string literals and ``LogSafe`` values.
///
/// It cannot be created from a runtime `String`, only from a literal, so content can enter a
/// log line only through a type someone has deliberately marked `LogSafe`.
public struct LogMessage: ExpressibleByStringInterpolation, Sendable {
    public let text: String

    public init(stringLiteral value: StaticString) {
        text = value.description
    }

    public init(stringInterpolation: StringInterpolation) {
        text = stringInterpolation.text
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        fileprivate var text = ""

        public init(literalCapacity: Int, interpolationCount: Int) {
            text.reserveCapacity(literalCapacity + interpolationCount * 8)
        }

        public mutating func appendLiteral(_ literal: StaticString) {
            text += literal.description
        }

        public mutating func appendInterpolation(_ value: some LogSafe) {
            text += value.logDescription
        }

        public mutating func appendInterpolation(_ value: (some LogSafe)?) {
            text += value?.logDescription ?? "nil"
        }
    }
}
