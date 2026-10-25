import Foundation

/// Everything that can go wrong reading or writing an eagar-rules or approval-ledger document.
///
/// Descriptions may quote values from the document (for example the offending enum value),
/// so they are for showing to the person editing the file, not for `EagarLog`.
public enum RulesError: Error, Sendable, Equatable, CustomStringConvertible {
    /// The bytes are not well-formed UTF-8 JSON.
    case invalidJSON(String)
    /// A bundled schema could not be found or loaded.
    case schemaUnavailable(String)
    /// The document does not conform to its JSON Schema.
    case schemaViolations([ValidationError])
    /// The document conforms to the schema but breaks a normative rule of Appendix F.
    case semanticViolations([SemanticIssue])
    /// The schema-valid JSON could not be mapped onto the model types (a codec bug).
    case decodingFailed(String)
    /// The model could not be serialised.
    case encodingFailed(String)

    public var description: String {
        switch self {
        case .invalidJSON(let detail):
            "Not valid JSON: \(detail)"
        case .schemaUnavailable(let detail):
            "Schema unavailable: \(detail)"
        case .schemaViolations(let errors):
            "Schema violations:\n" + errors.map { "  \($0)" }.joined(separator: "\n")
        case .semanticViolations(let issues):
            "Rule violations:\n" + issues.map { "  \($0)" }.joined(separator: "\n")
        case .decodingFailed(let detail):
            "Could not decode document: \(detail)"
        case .encodingFailed(let detail):
            "Could not encode document: \(detail)"
        }
    }
}
