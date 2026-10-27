import EagarCore
import Foundation

/// A date or date-time value from an iCalendar property (RFC 5545 §3.3.4, §3.3.5).
public struct ICalDate: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        /// `VALUE=DATE`: a whole local day. `date` is that day's start in the parse time zone.
        case allDay
        /// A UTC time (`…Z`).
        case utc
        /// A local time in the named time zone (`TZID=`), resolved by `TimeZone(identifier:)`.
        case zoned(String)
        /// A local time with no zone, read in the parse time zone.
        case floating
    }

    public let date: Date
    public let kind: Kind

    public init(date: Date, kind: Kind) {
        self.date = date
        self.kind = kind
    }

    public var isAllDay: Bool { kind == .allDay }
}

/// One content line: name, parameters and raw value. Names and parameter names are upper-cased.
public struct ICalProperty: Sendable, Hashable {
    public let name: String
    public let parameters: [String: String]
    /// The value as written, with line folding removed but escapes kept.
    public let rawValue: String

    public init(name: String, parameters: [String: String], rawValue: String) {
        self.name = name
        self.parameters = parameters
        self.rawValue = rawValue
    }

    /// The value with TEXT escapes (`\\`, `\;`, `\,`, `\n`) resolved.
    public var text: String { ICalendarParser.unescape(rawValue) }
}

/// A `VEVENT`, with the properties Eagar reads lifted out. Every property, including `X-`
/// extensions such as `X-CDB-STATUS`, stays available through ``property(_:)``.
public struct ICalEvent: Sendable, Hashable {
    public let uid: String?
    public let summary: String?
    public let eventDescription: String?
    public let location: String?
    public let url: URL?
    public let start: ICalDate?
    public let end: ICalDate?
    /// `DUE` (a VTODO property some producers, cdbooking included, put on loan events).
    public let due: ICalDate?
    /// `STATUS`, upper-cased (`TENTATIVE`, `CONFIRMED`, `CANCELLED`).
    public let status: String?
    public let lastModified: Date?
    public let properties: [ICalProperty]

    /// The first property called `name` (case-insensitive).
    public func property(_ name: String) -> ICalProperty? {
        let wanted = name.uppercased()
        return properties.first { $0.name == wanted }
    }
}

/// A parsed calendar.
public struct ICalendar: Sendable, Hashable {
    /// `X-WR-CALNAME`, if present.
    public let name: String?
    public let events: [ICalEvent]
    /// Lines that could not be read and were skipped.
    public let skippedLineCount: Int
}

/// Why a body could not be read as a calendar at all.
public enum ICalendarError: Error, Equatable, Sendable, LogSafe {
    /// No `BEGIN:VCALENDAR` (e.g. an HTML login page served instead of the feed).
    case notICalendar
    /// No `END:VCALENDAR`: the body was cut short. Refused, so a partial download can never
    /// be mistaken for a feed whose other events were deleted.
    case truncated
    /// The body is not UTF-8 text.
    case notText

    public var logDescription: String {
        switch self {
        case .notICalendar: "notICalendar"
        case .truncated: "truncated"
        case .notText: "notText"
        }
    }
}

/// An in-house RFC 5545 subset parser for feeds (BD-24: no third-party dependency).
///
/// Supported: line unfolding, TEXT escapes, quoted parameters, `VEVENT` with UID, SUMMARY,
/// DESCRIPTION, LOCATION, URL, DTSTART, DTEND, DUE, STATUS and LAST-MODIFIED; `VALUE=DATE`
/// all-day values, UTC `Z` times, `TZID=` times (IANA names, plus common Windows names) and
/// floating times. `VTIMEZONE` and nested components such as `VALARM` are skipped; a TZID is
/// resolved by name. Lines without a colon are skipped and counted. Recurrence (`RRULE`) is not
/// expanded: feeds Eagar reads (cdbooking, Canvas) emit one event per occurrence.
public enum ICalendarParser {
    /// Parses UTF-8 data. See ``parse(_:timeZone:)-(String,_)``.
    public static func parse(_ data: Data, timeZone: TimeZone) throws(ICalendarError) -> ICalendar {
        guard let text = String(data: data, encoding: .utf8) else { throw .notText }
        return try parse(text, timeZone: timeZone)
    }

    /// Parses `text`.
    /// - Parameter timeZone: used for all-day and floating values, and for TZIDs that cannot be
    ///   resolved. A calendar-level `X-WR-TIMEZONE` overrides it for floating values.
    public static func parse(_ text: String, timeZone: TimeZone) throws(ICalendarError) -> ICalendar {
        let lines = unfold(text)
        var sawCalendar = false
        var ended = false
        var calendarName: String?
        var floatingZone = timeZone
        var events: [ICalEvent] = []
        var skipped = 0
        // Component stack below VCALENDAR. Properties are collected only directly inside a VEVENT.
        var stack: [String] = []
        var current: [ICalProperty] = []

        for line in lines where !line.isEmpty {
            if ended { break }
            guard let property = parseLine(line) else {
                skipped += 1
                continue
            }
            switch property.name {
            case "BEGIN":
                let component = property.rawValue.uppercased()
                if !sawCalendar {
                    if component == "VCALENDAR" { sawCalendar = true }
                    continue
                }
                stack.append(component)
                if component == "VEVENT", stack.count == 1 { current = [] }
                continue
            case "END":
                let component = property.rawValue.uppercased()
                guard sawCalendar else { continue }
                if stack.isEmpty {
                    if component == "VCALENDAR" { ended = true }
                    continue
                }
                if let depth = stack.lastIndex(of: component) {
                    // Components left open inside this one (a VALARM without END) close with it.
                    if depth != stack.count - 1 { skipped += 1 }
                    stack.removeSubrange(depth...)
                    if component == "VEVENT", stack.isEmpty {
                        events.append(makeEvent(current, timeZone: timeZone, floatingZone: floatingZone))
                    }
                } else {
                    skipped += 1
                }
                continue
            default:
                break
            }
            guard sawCalendar else { continue }
            if stack.isEmpty {
                switch property.name {
                case "X-WR-CALNAME": calendarName = property.text
                case "X-WR-TIMEZONE": if let zone = resolveZone(property.text) { floatingZone = zone }
                default: break
                }
            } else if stack == ["VEVENT"] {
                current.append(property)
            }
        }
        guard sawCalendar else { throw .notICalendar }
        guard ended else { throw .truncated }
        return ICalendar(name: calendarName, events: events, skippedLineCount: skipped)
    }

    // MARK: Lines

    /// Splits on CRLF, CR or LF and joins folded lines (a line starting with a space or tab
    /// continues the previous one, minus that one character).
    static func unfold(_ text: String) -> [String] {
        var result: [String] = []
        let normalised = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for raw in normalised.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t", !result.isEmpty {
                result[result.count - 1] += raw.dropFirst()
            } else {
                result.append(String(raw))
            }
        }
        return result
    }

    /// `NAME;PARAM=VALUE;PARAM="QUOTED:VALUE":value`. Returns nil for a line with no colon
    /// outside quotes, or an empty name.
    static func parseLine(_ line: String) -> ICalProperty? {
        var inQuotes = false
        var colon: String.Index?
        for index in line.indices {
            let character = line[index]
            if character == "\"" { inQuotes.toggle() }
            if character == ":", !inQuotes { colon = index; break }
        }
        guard let colon else { return nil }
        let head = line[..<colon]
        let value = String(line[line.index(after: colon)...])
        let parts = splitOutsideQuotes(head, separator: ";")
        guard let rawName = parts.first?.trimmingCharacters(in: .whitespaces), !rawName.isEmpty,
              rawName.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
        else { return nil }
        var parameters: [String: String] = [:]
        for part in parts.dropFirst() {
            guard let equals = part.firstIndex(of: "=") else { continue }
            let key = part[..<equals].trimmingCharacters(in: .whitespaces).uppercased()
            var paramValue = String(part[part.index(after: equals)...])
            if paramValue.hasPrefix("\""), paramValue.hasSuffix("\""), paramValue.count >= 2 {
                paramValue = String(paramValue.dropFirst().dropLast())
            }
            parameters[key] = paramValue
        }
        return ICalProperty(name: rawName.uppercased(), parameters: parameters, rawValue: value)
    }

    private static func splitOutsideQuotes(_ text: Substring, separator: Character) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        for character in text {
            if character == "\"" { inQuotes.toggle() }
            if character == separator, !inQuotes {
                parts.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        parts.append(current)
        return parts
    }

    /// Resolves TEXT escapes (RFC 5545 §3.3.11). An unknown escape keeps the escaped character.
    static func unescape(_ value: String) -> String {
        var result = ""
        var escaping = false
        for character in value {
            if escaping {
                switch character {
                case "n", "N": result.append("\n")
                default: result.append(character)
                }
                escaping = false
            } else if character == "\\" {
                escaping = true
            } else {
                result.append(character)
            }
        }
        if escaping { result.append("\\") }
        return result
    }

    // MARK: Events

    private static func makeEvent(_ properties: [ICalProperty], timeZone: TimeZone, floatingZone: TimeZone) -> ICalEvent {
        func first(_ name: String) -> ICalProperty? { properties.first { $0.name == name } }
        func text(_ name: String) -> String? {
            first(name).map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        }
        func date(_ name: String) -> ICalDate? {
            first(name).flatMap { parseDate($0, timeZone: timeZone, floatingZone: floatingZone) }
        }
        let url = first("URL").flatMap { URL(string: $0.rawValue.trimmingCharacters(in: .whitespaces)) }
        return ICalEvent(
            uid: text("UID"),
            summary: text("SUMMARY"),
            eventDescription: text("DESCRIPTION"),
            location: text("LOCATION"),
            url: url,
            start: date("DTSTART"),
            end: date("DTEND"),
            due: date("DUE"),
            status: text("STATUS")?.uppercased(),
            lastModified: date("LAST-MODIFIED")?.date,
            properties: properties
        )
    }

    /// Reads a DATE or DATE-TIME property value.
    static func parseDate(_ property: ICalProperty, timeZone: TimeZone, floatingZone: TimeZone) -> ICalDate? {
        let value = property.rawValue.trimmingCharacters(in: .whitespaces)
        let isDateOnly = property.parameters["VALUE"]?.uppercased() == "DATE" || (value.count == 8 && !value.contains("T"))
        let digits = value.filter(\.isNumber)
        if isDateOnly {
            guard digits.count >= 8, let components = components(digits, time: false) else { return nil }
            return makeDate(components, in: timeZone).map { ICalDate(date: $0, kind: .allDay) }
        }
        guard digits.count >= 14, let components = components(digits, time: true) else { return nil }
        if value.uppercased().hasSuffix("Z") {
            return makeDate(components, in: TimeZone(identifier: "UTC")!).map { ICalDate(date: $0, kind: .utc) }
        }
        if let tzid = property.parameters["TZID"] {
            if let zone = resolveZone(tzid) {
                return makeDate(components, in: zone).map { ICalDate(date: $0, kind: .zoned(zone.identifier)) }
            }
            return makeDate(components, in: timeZone).map { ICalDate(date: $0, kind: .floating) }
        }
        return makeDate(components, in: floatingZone).map { ICalDate(date: $0, kind: .floating) }
    }

    private static func components(_ digits: String, time: Bool) -> DateComponents? {
        let chars = Array(digits)
        func number(_ range: Range<Int>) -> Int? { Int(String(chars[range])) }
        guard let year = number(0 ..< 4), let month = number(4 ..< 6), let day = number(6 ..< 8),
              (1 ... 12).contains(month), (1 ... 31).contains(day)
        else { return nil }
        var components = DateComponents(year: year, month: month, day: day)
        if time {
            guard let hour = number(8 ..< 10), let minute = number(10 ..< 12), let second = number(12 ..< 14),
                  (0 ... 23).contains(hour), (0 ... 59).contains(minute), (0 ... 60).contains(second)
            else { return nil }
            components.hour = hour
            components.minute = minute
            components.second = min(second, 59)
        }
        return components
    }

    private static func makeDate(_ components: DateComponents, in zone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: components)
    }

    /// Windows zone names some producers (Outlook, Exchange) write as TZIDs.
    private static let windowsZones: [String: String] = [
        "GMT STANDARD TIME": "Europe/London",
        "IRISH STANDARD TIME": "Europe/Dublin",
        "W. EUROPE STANDARD TIME": "Europe/Berlin",
        "ROMANCE STANDARD TIME": "Europe/Paris",
        "CENTRAL EUROPE STANDARD TIME": "Europe/Budapest",
        "EASTERN STANDARD TIME": "America/New_York",
        "CENTRAL STANDARD TIME": "America/Chicago",
        "MOUNTAIN STANDARD TIME": "America/Denver",
        "PACIFIC STANDARD TIME": "America/Los_Angeles",
        "UTC": "UTC",
    ]

    /// Resolves a TZID: IANA name (optionally quoted or with a leading `/`), else a known
    /// Windows name, else nil.
    static func resolveZone(_ tzid: String) -> TimeZone? {
        var name = tzid.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("\""), name.hasSuffix("\""), name.count >= 2 { name = String(name.dropFirst().dropLast()) }
        while name.hasPrefix("/") { name.removeFirst() }
        if let zone = TimeZone(identifier: name) { return zone }
        if let mapped = windowsZones[name.uppercased()] { return TimeZone(identifier: mapped) }
        return nil
    }
}
