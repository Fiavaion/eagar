import CloudKit
import EagarCore
import Foundation

/// The CloudKit zone holding PersonalStore records (PRD §7.5).
public enum SyncZone {
    public static let name = "EagarPersonal"
    public static var id: CKRecordZone.ID { CKRecordZone.ID(zoneName: name) }
}

/// Field name carrying each record's data class, so a receiving device can re-check it.
public let syncDataClassField = "eagarDataClass"

/// Converts between `SyncFields` and `CKRecord`.
///
/// Encoding refuses college data outright: this is the second line of defence behind
/// `SyncRegistry`, which already refuses to attach a sync engine to CollegeStore.
public enum RecordCodec {
    /// Writes `fields` into `record`. Fields in `encrypted` go into `encryptedValues` (BD-02).
    public static func write(
        _ fields: SyncFields, dataClass: DataClass, encrypted: Set<String>, into record: CKRecord
    ) throws(SyncError) {
        guard dataClass != .college else {
            EagarLog(.store).fault("refused to encode a college record for CloudKit")
            throw .collegeRecordRefused
        }
        record[syncDataClassField] = dataClass.rawValue
        for (name, value) in fields {
            if encrypted.contains(name) {
                record.encryptedValues[name] = value.recordValue
            } else {
                record[name] = value.recordValue
            }
        }
    }

    /// Reads the declared fields from `record`, decoding each as its kind.
    public static func read(
        _ record: CKRecord, kinds: [String: SyncFieldKind], encrypted: Set<String>
    ) throws(SyncError) -> (fields: SyncFields, dataClass: DataClass) {
        // A record without a class, or with an unknown one, reads as college and is refused.
        let dataClass = (record[syncDataClassField] as? String).flatMap(DataClass.init(rawValue:)) ?? .college
        guard dataClass != .college else { throw .collegeRecordRefused }
        var fields: SyncFields = [:]
        for (name, kind) in kinds {
            let raw: Any? = encrypted.contains(name) ? record.encryptedValues[name] : record[name]
            fields[name] = SyncValue.from(raw, kind: kind)
        }
        return (fields, dataClass)
    }
}
