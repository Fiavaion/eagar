import EagarCalendar
import EagarCore
import Foundation

/// The kinds of feed the pipeline reads (PRD §7.3 `Source.kind`, feed subset).
public enum FeedKind: String, Codable, Sendable, CaseIterable, LogSafe {
    /// cdbooking per Appendix E: JSON endpoint with an iCal fallback. Always `college` (BD-15).
    case cdbooking
    /// The Canvas personal calendar feed. Always `college` (FR-CANVAS-02).
    case canvas
    /// Any other iCalendar feed; classed by host (FR-CORE-04).
    case iCalendar

    public var logDescription: String { rawValue }
}

/// Whose profile a source is being set up for (FR-CORE-04).
public enum ProfileKind: String, Codable, Sendable, CaseIterable, LogSafe {
    /// Mark, who has authority to use local AI on his own college data (OD-2).
    case owner
    /// Any other user profile, e.g. a staff pilot without institutional approval: rules only.
    case other

    public var logDescription: String { rawValue }
}

/// Hosts whose feeds are college sources (FR-CORE-04).
public enum FeedCollegeDomains {
    /// NCAD's Canvas host. To verify on NCAD's instance (PRD §12.1); Canvas and cdbooking
    /// sources are college by kind whatever their host, so a wrong guess here cannot leak.
    public static let canvasHost = "ncad.instructure.com"

    /// `ncad.ie`, `cdbooking.com` and NCAD's Canvas host, on top of the calendar list.
    public static let `default`: Set<String> = CollegeDomains.default.union(["cdbooking.com", canvasHost])

    /// Whether `host` is one of `domains` or a subdomain of one. Case-insensitive.
    public static func matches(host: String, domains: Set<String> = Self.default) -> Bool {
        CollegeDomains.matches(host.lowercased(), domains: domains)
    }
}

/// The class and processing mode a new source starts with, before Mark confirms them.
public struct FeedSourceDefaults: Sendable, Hashable {
    public let dataClass: DataClass
    public let processingMode: ProcessingMode

    public init(dataClass: DataClass, processingMode: ProcessingMode) {
        self.dataClass = dataClass
        self.processingMode = processingMode
    }

    /// The `Boundary` implied by the class (PRD Glossary).
    public var boundary: Boundary { dataClass.isLocalOnly ? .localOnly : .cloudAllowed }

    /// FR-CORE-04 defaulting. A source is college when its kind is cdbooking or Canvas, or its
    /// host matches the college domain list. College sources get `localAI` for the owner and
    /// `rulesOnly` for anyone else. Other feeds are `personal`: `cloudAllowed` for the owner
    /// (BD-05, still subject to per-feature consent) and `rulesOnly` for anyone else.
    public static func proposed(
        kind: FeedKind, host: String?, profile: ProfileKind, collegeDomains: Set<String> = FeedCollegeDomains.default
    ) -> FeedSourceDefaults {
        let isCollege = kind != .iCalendar || host.map { FeedCollegeDomains.matches(host: $0, domains: collegeDomains) } ?? false
        switch (isCollege, profile) {
        case (true, .owner): return FeedSourceDefaults(dataClass: .college, processingMode: .localAI)
        case (true, .other): return FeedSourceDefaults(dataClass: .college, processingMode: .rulesOnly)
        case (false, .owner): return FeedSourceDefaults(dataClass: .personal, processingMode: .cloudAllowed)
        case (false, .other): return FeedSourceDefaults(dataClass: .personal, processingMode: .rulesOnly)
        }
    }
}

/// A configured feed, as a value. Its URL and tokens are never part of it: they live in the
/// Keychain under the source's ``SourceID`` (invariant 6).
public struct FeedSource: Sendable, Hashable, Identifiable, Classified {
    public let id: SourceID
    public let kind: FeedKind
    public let dataClass: DataClass
    public let processingMode: ProcessingMode

    public init(id: SourceID = SourceID(), kind: FeedKind, dataClass: DataClass, processingMode: ProcessingMode) {
        self.id = id
        self.kind = kind
        // cdbooking and Canvas are college whatever the caller passes (BD-15, FR-CANVAS-02).
        let resolvedClass = kind == .iCalendar ? dataClass : .college
        self.dataClass = resolvedClass
        // College data never goes to a cloud model (BD-04): a college source is local AI or
        // rules only, whatever mode the caller asked for.
        self.processingMode = resolvedClass.isLocalOnly && processingMode == .cloudAllowed ? .localAI : processingMode
    }

    /// A source with FR-CORE-04 defaults for `host`.
    public static func proposed(id: SourceID = SourceID(), kind: FeedKind, host: String?, profile: ProfileKind) -> FeedSource {
        let defaults = FeedSourceDefaults.proposed(kind: kind, host: host, profile: profile)
        return FeedSource(id: id, kind: kind, dataClass: defaults.dataClass, processingMode: defaults.processingMode)
    }

    public var sourceID: SourceID? { id }
    public var boundary: Boundary { dataClass.isLocalOnly ? .localOnly : .cloudAllowed }
}
