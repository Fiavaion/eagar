/// Every place in the codebase that derives a record or payload from classified inputs.
///
/// FR-CORE-03 requires a unit test per derivation. Adding a case here without a test whose
/// name contains `Derivation_<case>` fails `Tools/lint.sh`.
public enum DerivationID: String, Sendable, CaseIterable, LogSafe {
    /// The effective class of an AI request (router taint rule, BD-06).
    case aiRequestPayload
    /// The class of a privacy-ledger entry describing an AI call (BD-19).
    case ledgerEntry
    /// Busy blocks, free slots and breakpoints computed from classified events (FR-CAL-03).
    case calendarAvailability

    public var logDescription: String { rawValue }
}

/// The only sanctioned way for feature code to compute a derived class.
public enum Taint {
    /// The most restrictive class among `inputs` (BD-03).
    public static func derive(_ derivation: DerivationID, from inputs: some Sequence<DataClass>) -> DataClass {
        DataClass.max(of: inputs)
    }

    /// Convenience over classified values.
    public static func derive(_ derivation: DerivationID, from inputs: [any Classified]) -> DataClass {
        DataClass.max(of: inputs.map(\.dataClass))
    }
}
