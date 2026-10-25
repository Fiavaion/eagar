import Foundation

/// Reads and writes eagar-rules and approval-ledger documents.
///
/// Every read and every write is checked against the bundled JSON Schema (canonical copy in
/// `docs/schemas/`), and rules documents also against ``RulesSemanticValidator``, so Eagar
/// neither accepts nor produces a file the Windows app would reject.
public enum EagarRulesCodec {
    /// Resource name of the rules schema.
    public static let rulesSchemaName = "eagar-rules-1.0.schema"
    /// Resource name of the approval-ledger schema.
    public static let ledgerSchemaName = "eagar-approval-ledger-1.0.schema"

    static let rulesValidator = loadValidator(rulesSchemaName)
    static let ledgerValidator = loadValidator(ledgerSchemaName)

    /// Validates and decodes a rules document. Semantic warnings do not throw; see
    /// ``RulesSemanticValidator/issues(in:)``.
    public static func decode(_ data: Data) throws(RulesError) -> RulesDocument {
        let document = try decodeChecked(RulesDocument.self, from: data, validator: rulesValidator.get())
        let errors = RulesSemanticValidator.errors(in: document)
        guard errors.isEmpty else { throw .semanticViolations(errors) }
        return document
    }

    /// Encodes a rules document as sorted, pretty-printed JSON, refusing one that is invalid.
    public static func encode(_ document: RulesDocument) throws(RulesError) -> Data {
        let errors = RulesSemanticValidator.errors(in: document)
        guard errors.isEmpty else { throw .semanticViolations(errors) }
        return try encodeChecked(document, validator: rulesValidator.get())
    }

    /// Validates and decodes an approval-ledger export.
    public static func decodeLedger(_ data: Data) throws(RulesError) -> ApprovalLedgerExport {
        try decodeChecked(ApprovalLedgerExport.self, from: data, validator: ledgerValidator.get())
    }

    /// Encodes an approval-ledger export, refusing one that is invalid.
    public static func encodeLedger(_ export: ApprovalLedgerExport) throws(RulesError) -> Data {
        try encodeChecked(export, validator: ledgerValidator.get())
    }

    /// The bundled schema text, byte for byte.
    public static func schemaData(named name: String) throws(RulesError) -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources") else {
            throw .schemaUnavailable("\(name).json is missing from the bundle")
        }
        do {
            return try Data(contentsOf: url)
        } catch {
            throw .schemaUnavailable("\(name).json could not be read: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private static func loadValidator(_ name: String) -> Result<JSONSchemaValidator, RulesError> {
        do throws(RulesError) {
            let data = try schemaData(named: name)
            do {
                return .success(try JSONSchemaValidator(schemaData: data))
            } catch {
                return .failure(.schemaUnavailable("\(name).json: \(error)"))
            }
        } catch {
            return .failure(error)
        }
    }

    private static func decodeChecked<T: Decodable>(
        _ type: T.Type, from data: Data, validator: JSONSchemaValidator
    ) throws(RulesError) -> T {
        let instance = try JSONValue.parse(data)
        let violations = validator.validate(instance)
        guard violations.isEmpty else { throw .schemaViolations(violations) }
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw .decodingFailed(String(describing: error))
        }
    }

    private static func encodeChecked<T: Encodable>(_ value: T, validator: JSONSchemaValidator) throws(RulesError) -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data: Data
        do {
            data = try encoder.encode(value)
        } catch {
            throw .encodingFailed(String(describing: error))
        }
        let violations = validator.validate(try JSONValue.parse(data))
        guard violations.isEmpty else { throw .schemaViolations(violations) }
        return data
    }
}
