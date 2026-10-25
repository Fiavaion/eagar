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

/// What a rule does when it matches.
///
/// Each case carries exactly the field its `type` requires in the schema, so the model cannot
/// express an action the schema would refuse (a missing field, or a field for another type).
public enum Action: Sendable, Equatable, Codable {
    /// Adds `amount` (which may be negative) to the message's priority score.
    case adjustScore(amount: Double)
    /// Moves the message to the lane with this id.
    case setLane(laneId: String)
    /// Sets the thread's state.
    case setThreadState(ThreadState)
    /// Adds a label.
    case addLabel(String)
    /// Marks the message read.
    case markRead
    /// Suggests the playbook with this id.
    case suggestPlaybook(playbookId: String)
    /// Sets how loudly the message notifies.
    case notify(NotifyLevel)
    /// Mutes the thread until this time (a string, as written in the document).
    case muteUntil(String)

    /// The action's `type` value in JSON.
    public enum Kind: String, Sendable, Codable, CaseIterable {
        case adjustScore, setLane, setThreadState, addLabel, markRead, suggestPlaybook, notify, muteUntil
    }

    /// The states a thread can be set to.
    public enum ThreadState: String, Sendable, Codable, CaseIterable {
        case needsReply, waiting, delegated, done
    }

    /// Notification levels, quietest first.
    public enum NotifyLevel: String, Sendable, Codable, CaseIterable {
        case none, passive, active, timeSensitive
    }

    /// Which kind of action this is.
    public var kind: Kind {
        switch self {
        case .adjustScore: .adjustScore
        case .setLane: .setLane
        case .setThreadState: .setThreadState
        case .addLabel: .addLabel
        case .markRead: .markRead
        case .suggestPlaybook: .suggestPlaybook
        case .notify: .notify
        case .muteUntil: .muteUntil
        }
    }

    private enum CodingKeys: String, CodingKey {
        case type, amount, laneId, state, label, playbookId, level, until
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .type) {
        case .adjustScore: self = .adjustScore(amount: try container.decode(Double.self, forKey: .amount))
        case .setLane: self = .setLane(laneId: try container.decode(String.self, forKey: .laneId))
        case .setThreadState: self = .setThreadState(try container.decode(ThreadState.self, forKey: .state))
        case .addLabel: self = .addLabel(try container.decode(String.self, forKey: .label))
        case .markRead: self = .markRead
        case .suggestPlaybook: self = .suggestPlaybook(playbookId: try container.decode(String.self, forKey: .playbookId))
        case .notify: self = .notify(try container.decode(NotifyLevel.self, forKey: .level))
        case .muteUntil: self = .muteUntil(try container.decode(String.self, forKey: .until))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .type)
        switch self {
        case .adjustScore(let amount): try container.encode(amount, forKey: .amount)
        case .setLane(let laneId): try container.encode(laneId, forKey: .laneId)
        case .setThreadState(let state): try container.encode(state, forKey: .state)
        case .addLabel(let label): try container.encode(label, forKey: .label)
        case .markRead: break
        case .suggestPlaybook(let playbookId): try container.encode(playbookId, forKey: .playbookId)
        case .notify(let level): try container.encode(level, forKey: .level)
        case .muteUntil(let until): try container.encode(until, forKey: .until)
        }
    }
}
