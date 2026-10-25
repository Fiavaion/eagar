import Foundation

/// JSON and CSV exports of the privacy ledger for the DPIA (FR-PRIV-06).
public enum LedgerExport {
    public static let format = "eagar-privacy-ledger"
    public static let formatVersion = "1.0"

    public enum FileFormat: Sendable { case json, csv }

    private struct Document: Encodable {
        let format: String
        let formatVersion: String
        let exportedAt: Date
        let includesPayloads: Bool
        let entries: [LedgerRecord]
    }

    /// Encodes `records`. With `includePayloads == false`, every payload is omitted.
    public static func export(
        _ records: [LedgerRecord],
        as fileFormat: FileFormat,
        includePayloads: Bool,
        exportedAt: Date
    ) throws(LedgerError) -> Data {
        let rows = includePayloads ? records : records.map(\.withoutPayload)
        switch fileFormat {
        case .json:
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            do {
                return try encoder.encode(Document(
                    format: format, formatVersion: formatVersion, exportedAt: exportedAt,
                    includesPayloads: includePayloads, entries: rows
                ))
            } catch {
                throw .exportFailed
            }
        case .csv:
            return Data(csv(rows, exportedAt: exportedAt).utf8)
        }
    }

    static let csvColumns = [
        "id", "store", "at", "kind", "dataClass", "payloadClasses", "tier", "destination", "region",
        "modelID", "purpose", "consentID", "profileVersion", "inputCount", "detail", "inputTokens",
        "outputTokens", "cacheReadTokens", "cacheWriteTokens", "costMicroUSD", "durationMilliseconds",
        "outcome", "payload",
    ]

    private static func csv(_ rows: [LedgerRecord], exportedAt: Date) -> String {
        let dates = ISO8601DateFormatter()
        var lines = ["# \(format) \(formatVersion) exported \(dates.string(from: exportedAt))", csvColumns.joined(separator: ",")]
        for row in rows {
            let fields: [String?] = [
                row.id.uuidString, row.store.rawValue, dates.string(from: row.at), row.kind.rawValue,
                row.dataClass.rawValue, row.payloadClasses.map(\.rawValue).joined(separator: ";"),
                row.tier?.rawValue, row.destination, row.region, row.modelID, row.purpose,
                row.consentID?.uuidString, row.profileVersion.map(String.init), String(row.inputCount), row.detail,
                row.inputTokens.map(String.init), row.outputTokens.map(String.init),
                row.cacheReadTokens.map(String.init), row.cacheWriteTokens.map(String.init),
                row.costMicroUSD.map(String.init), row.durationMilliseconds.map(String.init),
                row.outcome.rawValue, row.payload,
            ]
            lines.append(fields.map { escape($0 ?? "") }.joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// RFC 4180 quoting.
    static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

extension LedgerRecord {
    var withoutPayload: LedgerRecord {
        var copy = self
        copy.payload = nil
        return copy
    }
}
