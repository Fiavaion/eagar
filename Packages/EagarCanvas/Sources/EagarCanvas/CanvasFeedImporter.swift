import EagarCalendar
import EagarCore
import EagarFeeds
import EagarSecurity
import EagarStore
import Foundation

/// Maps Canvas calendar-feed VEVENTs to entries (FR-CANVAS-02).
///
/// Canvas's feed format is general knowledge, to verify on NCAD's instance (RESEARCH.md,
/// Canvas): assignment UIDs look like `event-assignment-<id>`, calendar events like
/// `event-calendar-event-<id>`; assignment links carry `assignment` in their query, fragment or
/// path; the summary ends with the course code in brackets. Assignments put the due time in
/// DTSTART (DTEND equal or absent), or a `VALUE=DATE` day for all-day due dates.
public enum CanvasMapper {
    public static func kind(of event: ICalEvent) -> CanvasItemKind {
        let uid = event.uid?.lowercased() ?? ""
        if uid.contains("assignment") { return .assignment }
        if uid.contains("calendar-event") { return .event }
        let link = event.url?.absoluteString.lowercased() ?? ""
        return link.contains("assignment") ? .assignment : .event
    }

    /// `"Essay draft [SYN101]"` → (`"Essay draft"`, `"SYN101"`).
    public static func splitCourse(_ summary: String) -> (title: String, courseCode: String?) {
        let trimmed = summary.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasSuffix("]"), let open = trimmed.lastIndex(of: "[") else { return (trimmed, nil) }
        let code = trimmed[trimmed.index(after: open) ..< trimmed.index(before: trimmed.endIndex)].trimmingCharacters(in: .whitespaces)
        let title = trimmed[..<open].trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty, !title.isEmpty else { return (trimmed, nil) }
        return (title, code)
    }

    /// The numeric course ID from `include_contexts=course_501` or `/courses/501/`.
    public static func courseID(from url: URL?) -> String? {
        guard let text = url?.absoluteString else { return nil }
        for marker in ["course_", "/courses/"] {
            if let range = text.range(of: marker) {
                let digits = text[range.upperBound...].prefix { $0.isNumber }
                if !digits.isEmpty { return String(digits) }
            }
        }
        return nil
    }

    /// Entries for every usable VEVENT. Events without a UID or a start, and cancelled ones, are skipped.
    public static func entries(from calendar: ICalendar) -> [CanvasEntry] {
        calendar.events.compactMap { event in
            guard let uid = event.uid, let start = event.start, event.status != "CANCELLED" else { return nil }
            let kind = kind(of: event)
            let (title, code) = splitCourse(event.summary ?? "")
            return CanvasEntry(
                id: uid, kind: kind, title: title, courseCode: code, courseID: courseID(from: event.url),
                start: start.date, end: event.end?.date,
                dueAt: kind == .assignment ? (event.due ?? start).date : nil,
                isAllDay: start.isAllDay,
                pageURL: event.url.flatMap { $0.scheme?.lowercased() == "https" ? $0 : nil },
                lastModified: event.lastModified
            )
        }
    }

    /// The deadline for an assignment (FR-DL-01, origin `canvas`); nil for events.
    public static func deadline(for entry: CanvasEntry, source: SourceID) -> FeedDeadline? {
        guard entry.kind == .assignment, let due = entry.dueAt else { return nil }
        let title = entry.courseCode.map { "\(entry.title) (\($0))" } ?? entry.title
        return FeedDeadline(origin: .canvas, sourceID: source, externalID: entry.id, title: title, dueAt: due, isAllDay: entry.isAllDay, itemClass: .college)
    }
}

/// Keychain storage for the Canvas feed URL, a bearer secret (FR-CANVAS-01, invariant 6).
public struct CanvasSecrets: Sendable {
    private let store: any SecretStore

    public init(store: any SecretStore) {
        self.store = store
    }

    public func save(feedURL: Secret, for source: SourceID) throws(SecurityError) {
        try store.set(feedURL, for: .canvasFeedURL(source))
    }

    public func load(for source: SourceID) throws(SecurityError) -> Secret? {
        try store.get(.canvasFeedURL(source))
    }

    public func delete(for source: SourceID) throws(SecurityError) {
        try store.delete(.canvasFeedURL(source))
    }
}

/// Errors from a Canvas refresh. Content-free.
public enum CanvasImportError: Error, Equatable, Sendable, LogSafe {
    case notRegistered
    /// The feed URL is missing from the Keychain or is not https.
    case notConfigured
    /// `401`/`403`: Canvas refused the feed URL.
    case unauthorised
    /// `404`/`410`: the feed URL was reset or the feed is disabled; paste a new one.
    case revoked
    case fetch(FeedFetchError)
    /// The body was not a complete iCalendar file.
    case invalidPayload
    case store(StoreError)

    public var logDescription: String {
        switch self {
        case .notRegistered: "notRegistered"
        case .notConfigured: "notConfigured"
        case .unauthorised: "unauthorised"
        case .revoked: "revoked"
        case let .fetch(error): "fetch(\(error.logDescription))"
        case .invalidPayload: "invalidPayload"
        case let .store(error): "store(\(error.logDescription))"
        }
    }

    var health: FeedHealth {
        switch self {
        case .notConfigured: .notConfigured
        case .unauthorised: .unauthorised
        case .revoked: .revoked
        default: .failing
        }
    }
}

/// What a refresh did. Counts only.
public struct CanvasRefreshOutcome: Sendable, Hashable {
    public let changed: Bool
    public let entries: Int
    public let deleted: Int
    public let deadlines: DeadlineReconcileCounts
}

/// Imports the Canvas personal calendar feed into CollegeStore (FR-CANVAS-01, 02): entries, and
/// a deadline per assignment. Conditional GET with `ETag`; the feed is read in full each time,
/// so entries no longer in it are deleted. Rules only; no model calls (invariant 3).
public struct CanvasFeedImporter: Sendable {
    public let sourceID: SourceID
    private let secrets: CanvasSecrets
    private let stores: EagarStores
    private let fetcher: FeedFetcher
    private let clock: any EagarClock
    private let timeZone: TimeZone
    private let assignmentsAsDeadlines: Bool
    private let log = EagarLog(.feeds)

    /// - Parameters:
    ///   - timeZone: for all-day and floating values; the device's zone in the app.
    ///   - assignmentsAsDeadlines: turn assignment due dates into deadlines (default on).
    public init(
        sourceID: SourceID, secrets: any SecretStore, stores: EagarStores, fetcher: FeedFetcher = FeedFetcher(),
        clock: any EagarClock = SystemClock(), timeZone: TimeZone = .current, assignmentsAsDeadlines: Bool = true
    ) {
        self.sourceID = sourceID
        self.secrets = CanvasSecrets(store: secrets)
        self.stores = stores
        self.fetcher = fetcher
        self.clock = clock
        self.timeZone = timeZone
        self.assignmentsAsDeadlines = assignmentsAsDeadlines
    }

    /// The pasted feed URL, normalised (`webcal://` → `https://`), or nil if it is not https.
    public static func normalisedFeedURL(_ text: String) -> URL? {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("webcal://") { trimmed = "https://" + trimmed.dropFirst("webcal://".count) }
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https", let host = url.host(), !host.isEmpty else { return nil }
        return url
    }

    @discardableResult
    public func refresh() async throws(CanvasImportError) -> CanvasRefreshOutcome {
        let registry = FeedSourceRegistry(stores: stores)
        let now = clock.now()
        let loaded: FeedSourceState?
        do {
            loaded = try await registry.state(of: sourceID)
        } catch {
            throw .store(error)
        }
        guard var state = loaded else { throw .notRegistered }
        state.lastAttemptAt = now

        let outcome: CanvasRefreshOutcome
        do throws(CanvasImportError) {
            outcome = try await fetchAndApply(state: &state, now: now)
        } catch {
            log.notice("canvas refresh failed: \(error)")
            state.health = error.health
            try? await registry.save(state)
            throw error
        }
        state.health = .ok
        state.lastSuccessAt = now
        do {
            try await registry.save(state)
        } catch {
            throw .store(error)
        }
        log.info("canvas refresh: \(outcome.entries) entries, \(outcome.deleted) deleted")
        return outcome
    }

    private func fetchAndApply(state: inout FeedSourceState, now: Date) async throws(CanvasImportError) -> CanvasRefreshOutcome {
        let secret: Secret?
        do {
            secret = try secrets.load(for: sourceID)
        } catch {
            throw .notConfigured
        }
        guard let secret, let url = Self.normalisedFeedURL(secret.reveal()) else { throw .notConfigured }

        let result: FeedFetchResult
        do {
            result = try await fetcher.get(url, etag: state.etag, accept: "text/calendar")
        } catch .unauthorised {
            throw .unauthorised
        } catch .forbidden {
            throw .unauthorised
        } catch .gone {
            throw .revoked
        } catch .notFound {
            throw .revoked
        } catch {
            throw .fetch(error)
        }
        guard case let .modified(body, etag) = result else {
            return CanvasRefreshOutcome(changed: false, entries: 0, deleted: 0, deadlines: DeadlineReconcileCounts())
        }
        let calendar: ICalendar
        do {
            calendar = try ICalendarParser.parse(body, timeZone: timeZone)
        } catch {
            throw .invalidPayload
        }
        let entries = CanvasMapper.entries(from: calendar)
        do {
            let counts = try await CanvasRepository(stores: stores).replace(with: entries, source: sourceID, now: now)
            let deadlines = assignmentsAsDeadlines ? entries.compactMap { CanvasMapper.deadline(for: $0, source: sourceID) } : []
            let deadlineCounts = try await FeedDeadlineReconciler(stores: stores).upsert(deadlines, replacingAllFrom: (.canvas, sourceID), now: now)
            state.etag = etag
            return CanvasRefreshOutcome(changed: true, entries: counts.upserted, deleted: counts.deleted, deadlines: deadlineCounts)
        } catch {
            throw .store(error)
        }
    }

    /// Deletes the source's entries, deadlines, record and feed URL.
    public func disconnect() async throws(CanvasImportError) {
        do {
            try await CanvasRepository(stores: stores).removeAll(source: sourceID)
            _ = try await FeedDeadlineReconciler(stores: stores).removeAll(origin: .canvas, source: sourceID)
            try await FeedSourceRegistry(stores: stores).remove(sourceID)
        } catch {
            throw .store(error)
        }
        do {
            try secrets.delete(for: sourceID)
        } catch {
            throw .notConfigured
        }
    }
}
