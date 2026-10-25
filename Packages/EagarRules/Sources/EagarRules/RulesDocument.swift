import EagarCore
import Foundation

/// An eagar-rules v1 document (PRD Appendix F.1).
///
/// Date-times are kept as the RFC 3339 strings found in the file so that a document
/// round-trips exactly; the schema has already checked their format.
public struct RulesDocument: Sendable, Equatable, Codable {
    /// The value of the root `format` key.
    public static let format = "eagar-rules"
    /// The version this build writes.
    public static let currentFormatVersion = "1.0"

    /// The optional root `$schema` URI.
    public var schemaURI: String?
    /// `1.x`; readers accept any minor version.
    public var formatVersion: String
    /// UUID of the document, stable across revisions.
    public var documentId: String
    /// Incremented on every save.
    public var revision: Int
    /// RFC 3339 date-time of the last save.
    public var updatedAt: String
    public var author: Author?
    /// The most restrictive class of anything in the document.
    public var dataClass: DataClass
    public var lanes: [Lane]?
    public var rules: [Rule]?
    public var guards: Guards?
    public var playbooks: [Playbook]?
    public var autonomy: [AutonomyGrant]?
    /// Institution policy profile; `nil` when absent or `null`.
    public var policy: InstitutionPolicy?
    /// Root keys starting `x-`. Consumers must preserve them and may ignore them.
    public var extensions: [String: JSONValue]

    public init(
        schemaURI: String? = nil,
        formatVersion: String = RulesDocument.currentFormatVersion,
        documentId: String,
        revision: Int,
        updatedAt: String,
        author: Author? = nil,
        dataClass: DataClass,
        lanes: [Lane]? = nil,
        rules: [Rule]? = nil,
        guards: Guards? = nil,
        playbooks: [Playbook]? = nil,
        autonomy: [AutonomyGrant]? = nil,
        policy: InstitutionPolicy? = nil,
        extensions: [String: JSONValue] = [:]
    ) {
        self.schemaURI = schemaURI
        self.formatVersion = formatVersion
        self.documentId = documentId
        self.revision = revision
        self.updatedAt = updatedAt
        self.author = author
        self.dataClass = dataClass
        self.lanes = lanes
        self.rules = rules
        self.guards = guards
        self.playbooks = playbooks
        self.autonomy = autonomy
        self.policy = policy
        self.extensions = extensions
    }

    private struct Key: CodingKey {
        let stringValue: String
        init(_ string: String) { stringValue = string }
        init?(stringValue: String) { self.stringValue = stringValue }
        var intValue: Int? { nil }
        init?(intValue: Int) { nil }

        static let schema = Key("$schema"), format = Key("format"), formatVersion = Key("formatVersion")
        static let documentId = Key("documentId"), revision = Key("revision"), updatedAt = Key("updatedAt")
        static let author = Key("author"), dataClass = Key("dataClass"), lanes = Key("lanes"), rules = Key("rules")
        static let guards = Key("guards"), playbooks = Key("playbooks"), autonomy = Key("autonomy"), policy = Key("policy")
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        schemaURI = try container.decodeIfPresent(String.self, forKey: .schema)
        formatVersion = try container.decode(String.self, forKey: .formatVersion)
        documentId = try container.decode(String.self, forKey: .documentId)
        revision = try container.decode(Int.self, forKey: .revision)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        author = try container.decodeIfPresent(Author.self, forKey: .author)
        dataClass = try container.decode(DataClass.self, forKey: .dataClass)
        lanes = try container.decodeIfPresent([Lane].self, forKey: .lanes)
        rules = try container.decodeIfPresent([Rule].self, forKey: .rules)
        guards = try container.decodeIfPresent(Guards.self, forKey: .guards)
        playbooks = try container.decodeIfPresent([Playbook].self, forKey: .playbooks)
        autonomy = try container.decodeIfPresent([AutonomyGrant].self, forKey: .autonomy)
        policy = try container.decodeIfPresent(InstitutionPolicy.self, forKey: .policy)
        var extensions: [String: JSONValue] = [:]
        for key in container.allKeys where key.stringValue.hasPrefix("x-") {
            extensions[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
        }
        self.extensions = extensions
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        try container.encodeIfPresent(schemaURI, forKey: .schema)
        try container.encode(Self.format, forKey: .format)
        try container.encode(formatVersion, forKey: .formatVersion)
        try container.encode(documentId, forKey: .documentId)
        try container.encode(revision, forKey: .revision)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encode(dataClass, forKey: .dataClass)
        try container.encodeIfPresent(lanes, forKey: .lanes)
        try container.encodeIfPresent(rules, forKey: .rules)
        try container.encodeIfPresent(guards, forKey: .guards)
        try container.encodeIfPresent(playbooks, forKey: .playbooks)
        try container.encodeIfPresent(autonomy, forKey: .autonomy)
        try container.encodeIfPresent(policy, forKey: .policy)
        for (key, value) in extensions where key.hasPrefix("x-") {
            try container.encode(value, forKey: Key(key))
        }
    }
}

/// The app that last wrote the document.
public struct Author: Sendable, Equatable, Codable {
    public var app: String?
    public var appVersion: String?
    public var platform: String?

    public init(app: String? = nil, appVersion: String? = nil, platform: String? = nil) {
        self.app = app
        self.appVersion = appVersion
        self.platform = platform
    }
}

/// A mail lane: which account it covers, how much it weighs and how it may be processed.
public struct Lane: Sendable, Equatable, Codable {
    public var id: String
    public var name: String
    public var match: LaneMatch
    public var weight: Double
    public var boundary: Boundary
    public var processingMode: ProcessingMode
    public var schedule: [TimeWindow]?
    /// Absent means `true`: new lanes start in dry-run.
    public var dryRun: Bool?

    public init(
        id: String, name: String, match: LaneMatch, weight: Double, boundary: Boundary,
        processingMode: ProcessingMode, schedule: [TimeWindow]? = nil, dryRun: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.match = match
        self.weight = weight
        self.boundary = boundary
        self.processingMode = processingMode
        self.schedule = schedule
        self.dryRun = dryRun
    }
}

/// Which account a lane covers.
public struct LaneMatch: Sendable, Equatable, Codable {
    public var accountAddress: String?
    public var accountDomain: String?

    public init(accountAddress: String? = nil, accountDomain: String? = nil) {
        self.accountAddress = accountAddress
        self.accountDomain = accountDomain
    }
}

/// Days and an `HH:MM` range.
public struct TimeWindow: Sendable, Equatable, Codable {
    public enum Day: String, Sendable, Codable, CaseIterable {
        case mon, tue, wed, thu, fri, sat, sun
    }

    public var days: [Day]?
    public var from: String?
    public var to: String?

    public init(days: [Day]? = nil, from: String? = nil, to: String? = nil) {
        self.days = days
        self.from = from
        self.to = to
    }
}
