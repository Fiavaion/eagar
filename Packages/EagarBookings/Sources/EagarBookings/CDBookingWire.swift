import EagarFeeds
import Foundation

/// RFC 3339 timestamps as cdbooking writes them (Appendix E.1), with or without fractional seconds.
enum RFC3339 {
    static func parse(_ text: String?) -> Date? {
        guard let text = text?.trimmingCharacters(in: .whitespaces), !text.isEmpty else { return nil }
        if let date = try? Date(text, strategy: .iso8601) { return date }
        return try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
    }
}

/// Decoding of `cdbooking.bookings.v1` (Appendix E.4). Only the fields Eagar uses are read;
/// `user` (name and roles) is ignored on purpose (least data).
enum CDBookingJSON {
    static let bookingsSchema = "cdbooking.bookings.v1"
    static let adminSummarySchema = "cdbooking.admin_summary.v1"

    struct Response: Decodable {
        let schema: String
        let bookings: [Booking]
        let deletedIDs: [String]?
        let nextSince: String?

        enum CodingKeys: String, CodingKey {
            case schema, bookings
            case deletedIDs = "deleted_ids"
            case nextSince = "next_since"
        }
    }

    struct Item: Decodable {
        let name: String?
    }

    struct Booking: Decodable {
        let id: String
        let kind: String?
        let status: String?
        let title: String?
        let items: [Item]?
        let department: String?
        let location: String?
        let start: String?
        let due: String?
        let end: String?
        let returnedAt: String?
        let updatedAt: String?
        let url: String?
        let extendURL: String?

        enum CodingKeys: String, CodingKey {
            case id, kind, status, title, items, department, location, start, due, end, url
            case returnedAt = "returned_at"
            case updatedAt = "updated_at"
            case extendURL = "extend_url"
        }

        var record: BookingRecord {
            let names = (items ?? []).compactMap(\.name)
            return BookingRecord(
                id: id,
                kind: BookingKind(rawValue: kind?.lowercased() ?? "") ?? .equipment,
                status: BookingStatus(wire: status ?? ""),
                title: title ?? names.first ?? "",
                itemNames: names,
                department: department,
                location: location,
                start: RFC3339.parse(start),
                due: RFC3339.parse(due),
                end: RFC3339.parse(end),
                returnedAt: RFC3339.parse(returnedAt),
                updatedAt: RFC3339.parse(updatedAt),
                pageURL: httpsURL(url),
                extendURL: httpsURL(extendURL)
            )
        }
    }

    struct Admin: Decodable {
        let schema: String
        let pendingApprovals: Int
        let overdueReturns: Int
        let url: String?

        enum CodingKeys: String, CodingKey {
            case schema, url
            case pendingApprovals = "pending_approvals"
            case overdueReturns = "overdue_returns"
        }
    }

    /// Decodes a bookings response; nil if it is not `cdbooking.bookings.v1` (E.6: Eagar detects
    /// `schema` strings, not hostnames).
    static func decodeBookings(_ data: Data) -> Response? {
        guard let response = try? JSONDecoder().decode(Response.self, from: data), response.schema == bookingsSchema else { return nil }
        return response
    }

    static func decodeAdmin(_ data: Data) -> Admin? {
        guard let admin = try? JSONDecoder().decode(Admin.self, from: data), admin.schema == adminSummarySchema else { return nil }
        return admin
    }

    /// Links are kept only when they are https.
    static func httpsURL(_ text: String?) -> URL? {
        guard let text, let url = URL(string: text), url.scheme?.lowercased() == "https" else { return nil }
        return url
    }
}

/// Mapping of the cdbooking iCal feed (Appendix E.3) to bookings.
enum CDBookingICal {
    /// `booking-{id}@cdbooking.com` → `id`. Other UIDs are used whole.
    static func bookingID(fromUID uid: String) -> String {
        var id = uid
        if let at = id.firstIndex(of: "@") { id = String(id[..<at]) }
        if id.hasPrefix("booking-") { id.removeFirst("booking-".count) }
        return id
    }

    /// `X-CDB-STATUS` when present, else `STATUS` (TENTATIVE → requested, CONFIRMED → approved,
    /// CANCELLED → cancelled).
    static func status(of event: ICalEvent) -> BookingStatus {
        if let raw = event.property("X-CDB-STATUS")?.text, !raw.isEmpty { return BookingStatus(wire: raw) }
        switch event.status {
        case "TENTATIVE": return .requested
        case "CONFIRMED": return .approved
        case "CANCELLED": return .cancelled
        default: return .unknown
        }
    }

    /// Kind from `X-CDB-KIND` if the feed sends it. Otherwise equipment: Appendix E.3 does not
    /// mark rooms, and treating an unmarked booking as a loan errs towards a reminder rather
    /// than a missed return.
    static func kind(of event: ICalEvent) -> BookingKind {
        event.property("X-CDB-KIND").flatMap { BookingKind(rawValue: $0.text.lowercased()) } ?? .equipment
    }

    static func records(from calendar: ICalendar) -> [BookingRecord] {
        calendar.events.compactMap { event in
            guard let uid = event.uid else { return nil }
            let kind = kind(of: event)
            let status = status(of: event)
            // Loans carry DUE, or DTEND is the due time (E.3). Rooms use DTEND as their end.
            let due = kind == .equipment ? (event.due ?? event.end)?.date : nil
            return BookingRecord(
                id: bookingID(fromUID: uid), kind: kind, status: status, title: event.summary ?? "",
                location: event.location, start: event.start?.date, due: due,
                end: kind == .room ? event.end?.date : nil,
                updatedAt: event.lastModified,
                pageURL: event.url.flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil }
            )
        }
    }
}
