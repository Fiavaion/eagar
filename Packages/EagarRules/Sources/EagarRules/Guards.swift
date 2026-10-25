import Foundation

/// Pre-send guard configuration (FR-SEND-04).
public struct Guards: Sendable, Equatable, Codable {
    public var internalDomains: [String]?
    public var wrongRecipient: GuardSetting?
    public var missingAttachment: GuardSetting?
    public var externalDomain: GuardSetting?
    public var largeReplyAll: LargeReplyAllGuard?
    public var lateNight: LateNightGuard?
    public var personalData: PersonalDataGuard?
    public var tone: GuardSetting?
    /// Always enabled and blocking when present; the schema refuses anything else (Appendix F rule 3).
    public var crossAccountLeak: GuardSetting?

    public init(
        internalDomains: [String]? = nil, wrongRecipient: GuardSetting? = nil,
        missingAttachment: GuardSetting? = nil, externalDomain: GuardSetting? = nil,
        largeReplyAll: LargeReplyAllGuard? = nil, lateNight: LateNightGuard? = nil,
        personalData: PersonalDataGuard? = nil, tone: GuardSetting? = nil,
        crossAccountLeak: GuardSetting? = nil
    ) {
        self.internalDomains = internalDomains
        self.wrongRecipient = wrongRecipient
        self.missingAttachment = missingAttachment
        self.externalDomain = externalDomain
        self.largeReplyAll = largeReplyAll
        self.lateNight = lateNight
        self.personalData = personalData
        self.tone = tone
        self.crossAccountLeak = crossAccountLeak
    }
}

/// What a guard does when it fires.
public enum GuardAction: String, Sendable, Codable, CaseIterable {
    case warn, confirm, block
}

/// The fields every guard has.
public struct GuardSetting: Sendable, Equatable, Codable {
    public var enabled: Bool?
    public var action: GuardAction?

    public init(enabled: Bool? = nil, action: GuardAction? = nil) {
        self.enabled = enabled
        self.action = action
    }

    /// The only setting `crossAccountLeak` may have.
    public static let crossAccountLeakRequired = GuardSetting(enabled: true, action: .block)
}

/// Fires on reply-all to more than `threshold` recipients.
public struct LargeReplyAllGuard: Sendable, Equatable, Codable {
    public var enabled: Bool?
    public var action: GuardAction?
    public var threshold: Int?

    public init(enabled: Bool? = nil, action: GuardAction? = nil, threshold: Int? = nil) {
        self.enabled = enabled
        self.action = action
        self.threshold = threshold
    }
}

/// Fires on sends during quiet hours and offers to hold them until `holdUntil`.
public struct LateNightGuard: Sendable, Equatable, Codable {
    public var enabled: Bool?
    public var action: GuardAction?
    public var quietHours: TimeWindow?
    public var holdUntil: String?

    public init(enabled: Bool? = nil, action: GuardAction? = nil, quietHours: TimeWindow? = nil, holdUntil: String? = nil) {
        self.enabled = enabled
        self.action = action
        self.quietHours = quietHours
        self.holdUntil = holdUntil
    }
}

/// Fires when outgoing text matches a personal-data pattern.
public struct PersonalDataGuard: Sendable, Equatable, Codable {
    public struct Pattern: Sendable, Equatable, Codable {
        public var name: String
        public var regex: String

        public init(name: String, regex: String) {
            self.name = name
            self.regex = regex
        }
    }

    public var enabled: Bool?
    public var action: GuardAction?
    public var patterns: [Pattern]?

    public init(enabled: Bool? = nil, action: GuardAction? = nil, patterns: [Pattern]? = nil) {
        self.enabled = enabled
        self.action = action
        self.patterns = patterns
    }
}
