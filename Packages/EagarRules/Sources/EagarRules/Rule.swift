import Foundation

/// A sender rule: when a condition holds, apply actions (Appendix F.3, FR-EMAIL-08).
public struct Rule: Sendable, Equatable, Codable {
    public var id: String
    public var description: String?
    /// Absent means `true`.
    public var enabled: Bool?
    public var priority: Int?
    public var laneIds: [String]?
    public var when: Condition
    public var then: [Action]

    public init(
        id: String, description: String? = nil, enabled: Bool? = nil, priority: Int? = nil,
        laneIds: [String]? = nil, when: Condition, then: [Action]
    ) {
        self.id = id
        self.description = description
        self.enabled = enabled
        self.priority = priority
        self.laneIds = laneIds
        self.when = when
        self.then = then
    }
}

/// A rule condition: a boolean combination of field tests.
public indirect enum Condition: Sendable, Equatable, Codable {
    case all([Condition])
    case any([Condition])
    case not(Condition)
    case leaf(field: Field, op: Operator, value: JSONValue)

    /// The message attribute a leaf tests.
    public enum Field: String, Sendable, Codable, CaseIterable {
        case fromAddress = "from.address"
        case fromDomain = "from.domain"
        case toAddress = "to.address"
        case toDomain = "to.domain"
        case ccCount = "cc.count"
        case subject
        case listId
        case providerLabel
        case providerCategory
        case hasAttachment
        case isReply
        case sentByMe
        case receivedAtHour = "receivedAt.hour"
        case receivedAtWeekday = "receivedAt.weekday"
        case body
    }

    /// How a leaf compares the field with its value.
    public enum Operator: String, Sendable, Codable, CaseIterable {
        case equals, notEquals, contains, startsWith, endsWith, matchesRegex, `in`, gt, lt, exists
    }

    private enum CodingKeys: String, CodingKey {
        case all, any, not, field, op, value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let children = try container.decodeIfPresent([Condition].self, forKey: .all) {
            self = .all(children)
        } else if let children = try container.decodeIfPresent([Condition].self, forKey: .any) {
            self = .any(children)
        } else if let child = try container.decodeIfPresent(Condition.self, forKey: .not) {
            self = .not(child)
        } else {
            self = .leaf(
                field: try container.decode(Field.self, forKey: .field),
                op: try container.decode(Operator.self, forKey: .op),
                value: try container.decode(JSONValue.self, forKey: .value)
            )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .all(let children): try container.encode(children, forKey: .all)
        case .any(let children): try container.encode(children, forKey: .any)
        case .not(let child): try container.encode(child, forKey: .not)
        case .leaf(let field, let op, let value):
            try container.encode(field, forKey: .field)
            try container.encode(op, forKey: .op)
            try container.encode(value, forKey: .value)
        }
    }
}

/// What a rule does when it matches. Which optional fields apply depends on ``type``.
public struct Action: Sendable, Equatable, Codable {
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case adjustScore, setLane, setThreadState, addLabel, markRead, suggestPlaybook, notify, muteUntil
    }

    public enum ThreadState: String, Sendable, Codable, CaseIterable {
        case needsReply, waiting, delegated, done
    }

    public enum NotifyLevel: String, Sendable, Codable, CaseIterable {
        case none, passive, active, timeSensitive
    }

    public var type: Kind
    public var amount: Double?
    public var laneId: String?
    public var state: ThreadState?
    public var label: String?
    public var playbookId: String?
    public var level: NotifyLevel?
    public var until: String?

    public init(
        type: Kind, amount: Double? = nil, laneId: String? = nil, state: ThreadState? = nil,
        label: String? = nil, playbookId: String? = nil, level: NotifyLevel? = nil, until: String? = nil
    ) {
        self.type = type
        self.amount = amount
        self.laneId = laneId
        self.state = state
        self.label = label
        self.playbookId = playbookId
        self.level = level
        self.until = until
    }
}
