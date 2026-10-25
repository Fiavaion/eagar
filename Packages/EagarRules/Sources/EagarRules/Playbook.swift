import EagarCore
import Foundation

/// A reply playbook (Appendix F.4). A playbook with `approvedAt == nil` must not produce drafts.
public struct Playbook: Sendable, Equatable, Codable {
    public struct Trigger: Sendable, Equatable, Codable {
        public var description: String?
        public var rule: Condition?

        public init(description: String? = nil, rule: Condition? = nil) {
            self.description = description
            self.rule = rule
        }
    }

    public struct RequiredFact: Sendable, Equatable, Codable {
        public enum Source: String, Sendable, Codable, CaseIterable {
            case thread, calendar, canvas, user
            case cdbookingAvailability = "cdbooking.availability"
            case cdbookingBooking = "cdbooking.booking"
        }

        public var name: String
        public var source: Source

        public init(name: String, source: Source) {
            self.name = name
            self.source = source
        }
    }

    public struct DecisionInput: Sendable, Equatable, Codable {
        public var name: String
        public var prompt: String?
        public var options: [String]

        public init(name: String, prompt: String? = nil, options: [String]) {
            self.name = name
            self.prompt = prompt
            self.options = options
        }
    }

    /// `{{factName}}` and `{{decision.name}}` placeholders are resolved at draft time.
    public struct Template: Sendable, Equatable, Codable {
        public var subject: String?
        public var body: String
        public var branches: [String: String]?

        public init(subject: String? = nil, body: String, branches: [String: String]? = nil) {
            self.subject = subject
            self.body = body
            self.branches = branches
        }
    }

    /// Which tier may fill the template's gaps.
    public enum AIFill: String, Sendable, Codable, CaseIterable {
        case none, local, cloudAllowed
    }

    public var id: String
    public var version: Int
    public var name: String
    public var category: String
    public var laneIds: [String]?
    public var trigger: Trigger
    public var requiredFacts: [RequiredFact]?
    public var decisionInputs: [DecisionInput]?
    public var template: Template
    public var aiFill: AIFill?
    public var guards: [String]?
    /// RFC 3339 date-time of Mark's approval; `nil` (written as JSON `null`) when unapproved.
    public var approvedAt: String?

    public init(
        id: String, version: Int, name: String, category: String, laneIds: [String]? = nil,
        trigger: Trigger, requiredFacts: [RequiredFact]? = nil, decisionInputs: [DecisionInput]? = nil,
        template: Template, aiFill: AIFill? = nil, guards: [String]? = nil, approvedAt: String?
    ) {
        self.id = id
        self.version = version
        self.name = name
        self.category = category
        self.laneIds = laneIds
        self.trigger = trigger
        self.requiredFacts = requiredFacts
        self.decisionInputs = decisionInputs
        self.template = template
        self.aiFill = aiFill
        self.guards = guards
        self.approvedAt = approvedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, version, name, category, laneIds, trigger, requiredFacts, decisionInputs, template, aiFill, guards, approvedAt
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(version, forKey: .version)
        try container.encode(name, forKey: .name)
        try container.encode(category, forKey: .category)
        try container.encodeIfPresent(laneIds, forKey: .laneIds)
        try container.encode(trigger, forKey: .trigger)
        try container.encodeIfPresent(requiredFacts, forKey: .requiredFacts)
        try container.encodeIfPresent(decisionInputs, forKey: .decisionInputs)
        try container.encode(template, forKey: .template)
        try container.encodeIfPresent(aiFill, forKey: .aiFill)
        try container.encodeIfPresent(guards, forKey: .guards)
        // Required by the schema even when unapproved, so write an explicit null.
        try container.encode(approvedAt, forKey: .approvedAt)
    }
}

/// Graded autonomy level (BD-12). Ordered L0 < L1 < L2 < L3.
public enum AutonomyLevel: String, Sendable, Codable, CaseIterable, Comparable {
    case l0 = "L0", l1 = "L1", l2 = "L2", l3 = "L3"

    private var rank: Int {
        switch self {
        case .l0: 0
        case .l1: 1
        case .l2: 2
        case .l3: 3
        }
    }

    public static func < (lhs: AutonomyLevel, rhs: AutonomyLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Autonomy earned for one category on one lane. Never authorises a send by itself:
/// every message still needs its own approval (BD-11, BD-12).
public struct AutonomyGrant: Sendable, Equatable, Codable {
    public struct Evidence: Sendable, Equatable, Codable {
        public var approvals: Int?
        public var medianEditRatio: Double?
        public var guardTriggers: Int?
        public var windowDays: Int?

        public init(approvals: Int? = nil, medianEditRatio: Double? = nil, guardTriggers: Int? = nil, windowDays: Int? = nil) {
            self.approvals = approvals
            self.medianEditRatio = medianEditRatio
            self.guardTriggers = guardTriggers
            self.windowDays = windowDays
        }
    }

    public var category: String
    public var laneId: String
    public var level: AutonomyLevel
    public var delayMinutes: Int?
    public var grantedAt: String
    public var evidence: Evidence?

    public init(
        category: String, laneId: String, level: AutonomyLevel, delayMinutes: Int? = nil,
        grantedAt: String, evidence: Evidence? = nil
    ) {
        self.category = category
        self.laneId = laneId
        self.level = level
        self.delayMinutes = delayMinutes
        self.grantedAt = grantedAt
        self.evidence = evidence
    }
}

/// Institution policy profile (FR-GOV-04).
public struct InstitutionPolicy: Sendable, Equatable, Codable {
    public var issuer: String?
    public var appliesToDomains: [String]?
    public var maxProcessingMode: ProcessingMode?
    public var forceDryRun: Bool?
    public var maxAutonomy: AutonomyLevel?
    public var learningAllowed: Bool?
    public var profileToCloudAllowed: Bool?

    public init(
        issuer: String? = nil, appliesToDomains: [String]? = nil, maxProcessingMode: ProcessingMode? = nil,
        forceDryRun: Bool? = nil, maxAutonomy: AutonomyLevel? = nil, learningAllowed: Bool? = nil,
        profileToCloudAllowed: Bool? = nil
    ) {
        self.issuer = issuer
        self.appliesToDomains = appliesToDomains
        self.maxProcessingMode = maxProcessingMode
        self.forceDryRun = forceDryRun
        self.maxAutonomy = maxAutonomy
        self.learningAllowed = learningAllowed
        self.profileToCloudAllowed = profileToCloudAllowed
    }
}
