import EagarCore
import Foundation

/// What was booked (Appendix E.4 `kind`).
public enum BookingKind: String, Codable, Sendable, CaseIterable, LogSafe {
    case equipment, room

    public var logDescription: String { rawValue }
}

/// A booking's state (Appendix E.4 `status`, E.3 `X-CDB-STATUS`). Raw values are the wire values.
public enum BookingStatus: String, Codable, Sendable, CaseIterable, LogSafe {
    case requested, approved, rejected
    case checkedOut = "checked_out"
    case returned, overdue, cancelled
    /// A value added to v1 after this build (Appendix E.1 allows additive changes).
    case unknown

    /// Reads a wire value; anything unrecognised is `unknown`, never an error.
    public init(wire: String) {
        self = BookingStatus(rawValue: wire.lowercased()) ?? .unknown
    }

    public var logDescription: String { rawValue }
}

/// One booking as read from cdbooking, JSON or iCal. A value; persisted as ``BookingItem``.
public struct BookingRecord: Sendable, Hashable, Identifiable {
    /// cdbooking's booking ID, e.g. `b_789`.
    public let id: String
    public let kind: BookingKind
    public let status: BookingStatus
    public let title: String
    /// Names of the items in the booking (JSON `items[].name`); empty from iCal.
    public let itemNames: [String]
    public let department: String?
    public let location: String?
    public let start: Date?
    /// The loan's due time. Rooms have no due time; they use `end`.
    public let due: Date?
    public let end: Date?
    public let returnedAt: Date?
    public let updatedAt: Date?
    /// The booking's page on cdbooking. Requires a login; not a secret.
    public let pageURL: URL?
    /// The extension request page (FR-BOOK-04).
    public let extendURL: URL?

    public init(
        id: String, kind: BookingKind, status: BookingStatus, title: String, itemNames: [String] = [], department: String? = nil,
        location: String? = nil, start: Date? = nil, due: Date? = nil, end: Date? = nil, returnedAt: Date? = nil,
        updatedAt: Date? = nil, pageURL: URL? = nil, extendURL: URL? = nil
    ) {
        self.id = id
        self.kind = kind
        self.status = status
        self.title = title
        self.itemNames = itemNames
        self.department = department
        self.location = location
        self.start = start
        self.due = due
        self.end = end
        self.returnedAt = returnedAt
        self.updatedAt = updatedAt
        self.pageURL = pageURL
        self.extendURL = extendURL
    }

    /// An equipment loan that is out (or overdue) and has a due time: the loans that get return
    /// reminders, a deadline, clash checks and the due-day Live Activity.
    public var isActiveLoan: Bool {
        kind == .equipment && due != nil && returnedAt == nil && (status == .checkedOut || status == .overdue)
    }

    /// Finished: returned, cancelled or rejected.
    public var isClosed: Bool {
        returnedAt != nil || status == .returned || status == .cancelled || status == .rejected
    }
}

/// A stored booking with its source and class, as a value.
public struct BookingSnapshot: Sendable, Hashable, Identifiable, Classified {
    public let sourceID: SourceID?
    public let booking: BookingRecord
    public let dataClass: DataClass

    public init(sourceID: SourceID, booking: BookingRecord, dataClass: DataClass = .college) {
        self.sourceID = sourceID
        self.booking = booking
        self.dataClass = dataClass
    }

    public var id: String { booking.id }
}
