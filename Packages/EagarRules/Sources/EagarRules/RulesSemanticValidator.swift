import EagarCore
import Foundation

/// A breach of an Appendix F rule that JSON Schema cannot express.
public struct SemanticIssue: Sendable, Equatable, CustomStringConvertible {
    public enum Code: String, Sendable, Equatable {
        /// Rule 1: an L3 grant on a `localOnly` lane. Refused.
        case autonomyL3OnLocalOnlyLane
        /// Rule 1: a grant above `policy.maxAutonomy`. Consumers ignore the grant.
        case autonomyAbovePolicyMaximum
        /// Rule 3: `crossAccountLeak` present but not enabled and blocking.
        case crossAccountLeakDisabled
    }

    public enum Severity: String, Sendable, Equatable {
        /// The document is refused.
        case error
        /// The document is accepted; the flagged element is ignored when applied.
        case warning
    }

    public let code: Code
    public let severity: Severity
    /// JSON Pointer to the offending element.
    public let instancePath: String
    public let message: String

    public var description: String {
        "\(instancePath): \(message)"
    }
}

/// Checks the normative rules of Appendix F that the schema cannot express.
///
/// Implemented here: rule 1 (autonomy limits) and rule 3 (`crossAccountLeak` cannot be
/// disabled, also enforced by the schema). Rules 2, 4, 5 and 6 govern the rules engine at
/// run time and belong to M3.
public enum RulesSemanticValidator {
    /// Every issue in `document`, errors and warnings alike.
    public static func issues(in document: RulesDocument) -> [SemanticIssue] {
        var issues: [SemanticIssue] = []
        let boundaries = Dictionary((document.lanes ?? []).map { ($0.id, $0.boundary) }, uniquingKeysWith: { first, _ in first })
        let maximum = document.policy?.maxAutonomy

        for (index, grant) in (document.autonomy ?? []).enumerated() {
            let path = "/autonomy/\(index)"
            if grant.level == .l3, boundaries[grant.laneId] == .localOnly {
                issues.append(SemanticIssue(
                    code: .autonomyL3OnLocalOnlyLane, severity: .error, instancePath: path,
                    message: "autonomy level L3 cannot be granted on lane \"\(grant.laneId)\" because its boundary is localOnly"
                ))
            }
            if let maximum, grant.level > maximum {
                issues.append(SemanticIssue(
                    code: .autonomyAbovePolicyMaximum, severity: .warning, instancePath: path,
                    message: "autonomy level \(grant.level.rawValue) exceeds the policy maximum \(maximum.rawValue) and will be ignored"
                ))
            }
        }

        if let leak = document.guards?.crossAccountLeak, leak != .crossAccountLeakRequired {
            issues.append(SemanticIssue(
                code: .crossAccountLeakDisabled, severity: .error, instancePath: "/guards/crossAccountLeak",
                message: "the cross-account leak guard cannot be disabled or softened; it must be enabled with action \"block\""
            ))
        }
        return issues
    }

    /// Only the issues that refuse the document.
    public static func errors(in document: RulesDocument) -> [SemanticIssue] {
        issues(in: document).filter { $0.severity == .error }
    }
}
