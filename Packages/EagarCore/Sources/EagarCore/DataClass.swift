/// The sensitivity class every persisted record and every AI payload carries (BD-03).
///
/// Cases are declared in ascending order of restrictiveness, and `Comparable` follows
/// that order, so `max` is always the most restrictive class.
public enum DataClass: String, Codable, Sendable, CaseIterable, Comparable {
    /// Public metadata (podcast RSS, YouTube titles). Any tier, subject to the source's own policy.
    case publicContent
    /// Lines of the About-me profile that Mark has approved (BD-10). Cloud AI as context.
    case approvedProfile
    /// Mark's own personal data. Cloud AI per feature, with consent.
    case personal
    /// NCAD-controlled data and anything derived from it. Local devices only.
    case college

    private var rank: Int {
        switch self {
        case .publicContent: 0
        case .approvedProfile: 1
        case .personal: 2
        case .college: 3
        }
    }

    public static func < (lhs: DataClass, rhs: DataClass) -> Bool {
        lhs.rank < rhs.rank
    }

    /// The taint rule: the most restrictive class among `classes`.
    ///
    /// An empty sequence carries no data, so it yields `.publicContent`, the identity of `max`.
    /// Prefer ``Taint/derive(_:from:)`` in feature code so the derivation is registered.
    public static func max(of classes: some Sequence<DataClass>) -> DataClass {
        classes.reduce(.publicContent) { Swift.max($0, $1) }
    }

    /// Whether data of this class may leave Mark's devices under any configuration.
    /// Only `college` is unconditionally local (OD-2).
    public var isLocalOnly: Bool { self == .college }
}
