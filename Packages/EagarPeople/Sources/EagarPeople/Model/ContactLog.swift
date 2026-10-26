import EagarCore
import Foundation
import SwiftData

/// How a contact-log entry came about.
public enum ContactLogKind: String, Codable, Sendable, CaseIterable {
    /// Mark tapped "we talked" (FR-PEOPLE-03).
    case manual
    /// Logged from a keep-in-touch nudge's "log contact" action (FR-PEOPLE-05).
    case nudge
}

/// A manual "we talked" entry (FR-PEOPLE-03). Always `personal`: Mark writes it himself.
///
/// The person is referenced by UUID, not a relationship, so the record syncs independently
/// and stays CloudKit-compatible.
@Model
public final class ContactLog: Classified {
    public var logUUID: UUID = UUID()
    public var personUUID: UUID?
    public var occurredAt: Date = Date.distantPast
    public var kindRaw: String = ContactLogKind.manual.rawValue
    /// Optional free text. Synced only in CloudKit `encryptedValues`.
    public var note: String = ""
    public var dataClassRaw: String = DataClass.college.rawValue
    public var createdAt: Date = Date.distantPast

    public init(
        logUUID: UUID = UUID(), personUUID: UUID, occurredAt: Date, kind: ContactLogKind = .manual,
        note: String = "", dataClass: DataClass = .personal, createdAt: Date
    ) {
        self.logUUID = logUUID
        self.personUUID = personUUID
        self.occurredAt = occurredAt
        kindRaw = kind.rawValue
        self.note = note
        dataClassRaw = dataClass.rawValue
        self.createdAt = createdAt
    }

    public var dataClass: DataClass { DataClass(rawValue: dataClassRaw) ?? .college }
    public var sourceID: SourceID? { nil }
    public var kind: ContactLogKind { ContactLogKind(rawValue: kindRaw) ?? .manual }

    public var snapshot: ContactLogSnapshot? {
        personUUID.map { ContactLogSnapshot(id: logUUID, personID: $0, occurredAt: occurredAt, kind: kind, dataClass: dataClass) }
    }
}

/// A `Sendable` value copy of a ``ContactLog``. The note is left out: nothing downstream needs it.
public struct ContactLogSnapshot: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let personID: UUID
    public let occurredAt: Date
    public let kind: ContactLogKind
    public let dataClass: DataClass

    public init(id: UUID = UUID(), personID: UUID, occurredAt: Date, kind: ContactLogKind = .manual, dataClass: DataClass = .personal) {
        self.id = id
        self.personID = personID
        self.occurredAt = occurredAt
        self.kind = kind
        self.dataClass = dataClass
    }
}
