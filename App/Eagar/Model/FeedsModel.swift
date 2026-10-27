import EagarBookings
import EagarBrief
import EagarCalendar
import EagarCanvas
import EagarCore
import EagarFeeds
import EagarSecurity
import Foundation
import Observation

/// What a loan's deadline row shows beyond the deadline itself (FR-BOOK-03, FR-BOOK-04).
struct LoanRowInfo: Equatable {
    let bookingID: String
    let status: BookingStatus
    let location: String?
    let pageURL: URL?
    let extendURL: URL?
    /// Set when the due time falls in busy time.
    let clash: ReturnClash?
    /// Mark accepted the proposed return time: the return reminder exists.
    let proposalAccepted: Bool
}

/// The college feeds (M2): cdbooking loans and the Canvas calendar feed. Setup, refresh, feed
/// health, return clashes, the admin summary and the due-day Live Activity.
///
/// Every record lives in CollegeStore and every secret in the Keychain; nothing here makes a
/// model call (invariant 3) or touches the sync engine (BD-02, B-8).
@MainActor
@Observable
final class FeedsModel {
    private(set) var booking: FeedSourceState?
    private(set) var canvas: FeedSourceState?
    private(set) var maskedBookingFeedURL: String?
    private(set) var maskedBookingToken: String?
    private(set) var maskedCanvasFeedURL: String?
    /// Every stored booking, soonest first.
    private(set) var loans: [BookingSnapshot] = []
    private(set) var canvasEntries: [CanvasEntry] = []
    /// Return clashes of active loans, by booking ID.
    private(set) var clashes: [String: ReturnClash] = [:]
    /// Counts only, when the cdbooking token has admin scope (FR-BOOK-06).
    private(set) var adminSummary: AdminSummary?
    /// Which cdbooking endpoint answered the last refresh in this session.
    private(set) var lastBookingPath: BookingFetchPath?
    private(set) var isRefreshing = false
    var failure: FeedsFailure?
    /// Called after a change Mark made (connect, remove, accept), so the brief recomposes.
    var onChange: (() -> Void)?

    private let services: AppServices
    private let planner: PlannerModel
    private let clock: any EagarClock
    private let calendar: Calendar
    private let log = EagarLog(.feeds)
    private var lastNetworkRefresh: Date?

    /// Activations closer together than this read the stores only; ETags make a refresh cheap,
    /// but there is no need to ask the servers every time the app comes forward.
    static let minimumRefreshInterval: TimeInterval = 5 * 60
    /// cdbooking writes floating and all-day times in Dublin time (Appendix E.1).
    static let cdbookingTimeZone = TimeZone(identifier: "Europe/Dublin") ?? .current

    init(services: AppServices, planner: PlannerModel, clock: any EagarClock, calendar: Calendar) {
        self.services = services
        self.planner = planner
        self.clock = clock
        self.calendar = calendar
        planner.onLoanDeadlineChanged = { [weak self] id in await self?.loanDeadlineChanged(id) }
    }

    var hasSources: Bool { booking != nil || canvas != nil }

    /// A feed needs Mark (token revoked, feed reset, secret missing).
    var needsAttention: Bool {
        (booking?.health.needsAttention ?? false) || (canvas?.health.needsAttention ?? false)
    }

    var canvasAssignmentCount: Int { canvasEntries.filter { $0.kind == .assignment }.count }
    var canvasEventCount: Int { canvasEntries.filter { $0.kind == .event }.count }
    var activeLoans: [BookingSnapshot] { loans.filter(\.booking.isActiveLoan) }

    // MARK: Refresh (FR-BOOK-02, FR-CANVAS-01)

    /// App activation and background refresh. Fetches every source unless one was fetched in
    /// the last few minutes (`force` skips that), then reloads, resyncs return reminders and
    /// updates the Live Activity. Failures are recorded as each source's health, never thrown.
    func refresh(force: Bool = false) async {
        let now = clock.now()
        if !force, let last = lastNetworkRefresh, now.timeIntervalSince(last) < Self.minimumRefreshInterval {
            await load()
            return
        }
        // Claimed before the first suspension, so a second activation meanwhile only reads.
        lastNetworkRefresh = now
        await loadSources()
        guard hasSources else {
            await load()
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }
        if let id = booking?.source.id { await fetchBooking(id) }
        if let id = canvas?.source.id { await fetchCanvas(id) }
        await load()
        await planner.deadlinesChanged(requestAuthorisation: false)
    }

    /// Reads sources, loans and Canvas entries from CollegeStore, recomputes clashes and
    /// updates the Live Activity. No network.
    func load() async {
        await loadSources()
        do {
            loans = try await BookingRepository(stores: services.stores).all()
            canvasEntries = try await CanvasRepository(stores: services.stores).all()
        } catch {
            log.error("reading feed items failed: \(error)")
            failure = .read
        }
        await computeClashes()
        await services.loanActivities.show(LoanLiveActivityPlanner.plan(loansStillOpen, now: clock.now(), calendar: calendar))
    }

    private func loadSources() async {
        do {
            let states = try await FeedSourceRegistry(stores: services.stores).all()
            booking = states.first { $0.source.kind == .cdbooking }
            canvas = states.first { $0.source.kind == .canvas }
        } catch {
            log.error("reading feed sources failed: \(error)")
            failure = .read
        }
        loadMaskedSecrets()
    }

    private func loadMaskedSecrets() {
        do throws(SecurityError) {
            var bookingCredentials: CDBookingCredentials?
            if let id = booking?.source.id { bookingCredentials = try CDBookingSecrets(store: services.secrets).load(for: id) }
            maskedBookingFeedURL = bookingCredentials.map { Self.maskedFeedAddress($0.feedURL) }
            maskedBookingToken = bookingCredentials?.apiToken.flatMap { $0.isEmpty ? nil : $0.masked }
            var canvasURL: Secret?
            if let id = canvas?.source.id { canvasURL = try CanvasSecrets(store: services.secrets).load(for: id) }
            maskedCanvasFeedURL = canvasURL.map(Self.maskedFeedAddress)
        } catch {
            log.error("reading feed secrets failed: \(error)")
            failure = .keychain
        }
    }

    /// A feed address for display: its host and the last four characters of the token in its
    /// last path component (without the extension), e.g. `cdbooking.com ••••9c2e`. The rest of
    /// the token is never shown.
    static func maskedFeedAddress(_ secret: Secret) -> String {
        let url = URL(string: secret.reveal())
        let host = url?.host() ?? ""
        let token = url.map { ($0.lastPathComponent as NSString).deletingPathExtension } ?? ""
        let tail = token.count > 8 ? String(token.suffix(4)) : ""
        return host.isEmpty ? "••••\(tail)" : "\(host) ••••\(tail)"
    }

    private func bookingSource(_ id: SourceID) -> CDBookingFeedSource {
        CDBookingFeedSource(sourceID: id, secrets: services.secrets, fetcher: services.feedFetcher, timeZone: Self.cdbookingTimeZone)
    }

    private func canvasImporter(_ id: SourceID) -> CanvasFeedImporter {
        CanvasFeedImporter(sourceID: id, secrets: services.secrets, stores: services.stores, fetcher: services.feedFetcher, clock: clock, timeZone: calendar.timeZone)
    }

    /// One cdbooking refresh and, with an API token, the admin summary. The source's health
    /// records any failure (BookingSync saves it), so Settings can show it.
    private func fetchBooking(_ id: SourceID) async {
        let source = bookingSource(id)
        let sync = BookingSync(stores: services.stores, clock: clock)
        do {
            lastBookingPath = try await sync.refresh(source).path
        } catch {
            log.notice("cdbooking refresh failed: \(error)")
            // A fetch failure is shown as the source's health; a store failure (the health
            // itself could not be saved) is shown as an alert.
            if case .store = error { failure = .save }
            return
        }
        do {
            adminSummary = try await sync.refreshAdminSummary(source)
        } catch {
            log.notice("cdbooking admin summary failed: \(error)")
            if case .store = error { failure = .save }
        }
    }

    private func fetchCanvas(_ id: SourceID) async {
        do {
            try await canvasImporter(id).refresh()
        } catch {
            log.notice("canvas refresh failed: \(error)")
            if case .store = error { failure = .save }
        }
    }

    // MARK: Setup (FR-BOOK-01, FR-CANVAS-01, FR-CORE-04)

    /// Adds cdbooking, or replaces its feed URL and token (after a 401 or 410). The secrets go
    /// to the Keychain; the source record holds neither. Returns whether it was saved.
    @discardableResult
    func connectBooking(feedURL: String, apiToken: String, requestNotifications: Bool = true) async -> Bool {
        guard let url = CDBookingFeedSource.normalisedFeedURL(feedURL) else {
            failure = .invalidURL
            return false
        }
        // cdbooking is college whatever the host (BD-15); Mark is the owner profile (OD-2).
        let source = booking?.source ?? FeedSource.proposed(kind: .cdbooking, host: url.host(), profile: .owner)
        let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
        // Register first: a failed registration leaves the Keychain untouched.
        guard await register(source, displayName: "cdbooking") else { return false }
        do {
            try CDBookingSecrets(store: services.secrets).save(
                CDBookingCredentials(feedURL: Secret(url.absoluteString), apiToken: token.isEmpty ? nil : Secret(token)), for: source.id
            )
        } catch {
            log.error("saving cdbooking secrets failed: \(error)")
            failure = .keychain
            if booking == nil { await unregister(source.id) }
            return false
        }
        lastNetworkRefresh = clock.now()
        await fetchBooking(source.id)
        await changed(requestNotifications: requestNotifications)
        return true
    }

    /// Adds the Canvas calendar feed, or replaces its URL. Returns whether it was saved.
    @discardableResult
    func connectCanvas(feedURL: String, requestNotifications: Bool = true) async -> Bool {
        guard let url = CanvasFeedImporter.normalisedFeedURL(feedURL) else {
            failure = .invalidURL
            return false
        }
        let source = canvas?.source ?? FeedSource.proposed(kind: .canvas, host: url.host(), profile: .owner)
        guard await register(source, displayName: "Canvas") else { return false }
        do {
            try CanvasSecrets(store: services.secrets).save(feedURL: Secret(url.absoluteString), for: source.id)
        } catch {
            log.error("saving the Canvas feed URL failed: \(error)")
            failure = .keychain
            if canvas == nil { await unregister(source.id) }
            return false
        }
        lastNetworkRefresh = clock.now()
        await fetchCanvas(source.id)
        await changed(requestNotifications: requestNotifications)
        return true
    }

    private func register(_ source: FeedSource, displayName: String) async -> Bool {
        do {
            try await FeedSourceRegistry(stores: services.stores).register(source, displayName: displayName, at: clock.now())
            return true
        } catch {
            log.error("registering a feed failed: \(error)")
            failure = .save
            return false
        }
    }

    /// Undoes the registration of a new source whose secret could not be saved.
    private func unregister(_ id: SourceID) async {
        do {
            try await FeedSourceRegistry(stores: services.stores).remove(id)
        } catch {
            log.error("removing a half-added feed failed: \(error)")
        }
    }

    /// Deletes cdbooking's bookings, loan deadlines, return reminders, record and both secrets.
    func removeBooking() async {
        guard let id = booking?.source.id else { return }
        do {
            try await BookingSync(stores: services.stores, clock: clock).disconnect(id)
        } catch {
            log.error("removing cdbooking failed: \(error)")
            failure = .save
        }
        do {
            try CDBookingSecrets(store: services.secrets).delete(for: id)
        } catch {
            log.error("deleting cdbooking secrets failed: \(error)")
            failure = .keychain
        }
        adminSummary = nil
        lastBookingPath = nil
        await changed(requestNotifications: false)
    }

    /// Deletes Canvas entries, their deadlines, the record and the feed URL.
    func removeCanvas() async {
        guard let id = canvas?.source.id else { return }
        do {
            try await canvasImporter(id).disconnect()
        } catch {
            log.error("removing Canvas failed: \(error)")
            failure = .save
        }
        await changed(requestNotifications: false)
    }

    private func changed(requestNotifications: Bool) async {
        await load()
        await planner.deadlinesChanged(requestAuthorisation: requestNotifications)
        onChange?()
    }

    // MARK: Loans, clashes and the brief (FR-BOOK-03, FR-BOOK-04, FR-BOOK-07)

    /// The deadline ID a loan's return deadline has (stable across refreshes).
    static func deadlineID(for loan: BookingSnapshot) -> UUID? {
        loan.sourceID.map { FeedDeadline.deadlineID(origin: .booking, sourceID: $0, externalID: loan.booking.id) }
    }

    /// Active loans whose return deadline Mark has not marked done.
    private var loansStillOpen: [BookingSnapshot] {
        activeLoans.filter { loan in
            guard let id = Self.deadlineID(for: loan), let row = planner.row(for: id) else { return true }
            return row.snapshot.status == .open
        }
    }

    func loan(forDeadline id: UUID) -> BookingSnapshot? {
        loans.first { Self.deadlineID(for: $0) == id }
    }

    func loanInfo(forDeadline id: UUID) -> LoanRowInfo? {
        guard let loan = loan(forDeadline: id) else { return nil }
        let clash = clashes[loan.booking.id]
        return LoanRowInfo(
            bookingID: loan.booking.id, status: loan.booking.status, location: loan.booking.location, pageURL: loan.booking.pageURL,
            extendURL: loan.booking.extendURL, clash: clash,
            proposalAccepted: isAccepted(loan, clash: clash)
        )
    }

    /// Checks each upcoming loan's due time against busy time on every calendar (FR-BOOK-04).
    private func computeClashes() async {
        let now = clock.now()
        let upcoming = activeLoans.filter { ($0.booking.due ?? .distantPast) > now }
        guard let last = upcoming.compactMap(\.booking.due).max() else {
            clashes = [:]
            return
        }
        let window = DateInterval(start: now, end: last)
        let busy = AvailabilityEngine.busyBlocks(for: await planner.classifiedEvents(in: window), in: window, calendar: calendar)
        var found: [String: ReturnClash] = [:]
        for loan in upcoming {
            if let clash = ReturnClashCheck.check(loan, busy: busy, now: now, calendar: calendar) { found[loan.booking.id] = clash }
        }
        clashes = found
    }

    /// The loan's open return reminder is at the currently proposed slot.
    private func isAccepted(_ loan: BookingSnapshot, clash: ReturnClash?) -> Bool {
        guard let slot = clash?.proposedSlot, let source = loan.sourceID,
              let row = planner.row(for: LoanReminders.returnReminderID(source: source, bookingID: loan.booking.id))
        else { return false }
        return row.snapshot.status == .open && row.snapshot.dueAt == slot.start
    }

    /// Accepts the proposed return time: the loan's return reminder (origin `booking`, the
    /// loan's source) at the start of the slot, reminding 15 minutes before and at the time.
    /// A later slot moves the same reminder. It goes when the loan is returned, marked done or
    /// cdbooking is removed. Local only; nothing is sent to cdbooking.
    func acceptProposedReturn(bookingID: String) async {
        guard let loan = loans.first(where: { $0.booking.id == bookingID }), let source = loan.sourceID,
              let slot = clashes[bookingID]?.proposedSlot, loansStillOpen.contains(loan)
        else { return }
        let item = LoanReminders.returnReminder(
            bookingID: bookingID, title: String(localized: "Return \(loan.booking.title)"), source: source, at: slot.start
        )
        do {
            _ = try await FeedDeadlineReconciler(stores: services.stores).upsert([item], reopening: [item.id], now: clock.now())
        } catch {
            log.error("saving a return reminder failed: \(error)")
            failure = .save
            return
        }
        await planner.deadlinesChanged(requestAuthorisation: true)
        onChange?()
    }

    /// Mark changed a loan deadline (done, snoozed, rescheduled, deleted): a loan he dealt
    /// with closes its return reminder, and the Live Activity follows (FR-BOOK-07).
    func loanDeadlineChanged(_ id: UUID) async {
        if let loan = loan(forDeadline: id), let source = loan.sourceID, planner.row(for: id)?.snapshot.status != .open {
            let reminder = LoanReminders.returnReminderID(source: source, bookingID: loan.booking.id)
            if planner.row(for: reminder)?.snapshot.status == .open { await planner.markDone(reminder) }
        }
        await load()
        onChange?()
    }

    /// Active loans for the brief's Loans due section, with the earlier return time if the
    /// due time clashes.
    var briefLoans: [BriefLoan] {
        activeLoans.compactMap { loan in
            guard let due = loan.booking.due else { return nil }
            return BriefLoan(
                id: loan.booking.id, deadlineID: Self.deadlineID(for: loan)?.uuidString, title: loan.booking.title, dueAt: due,
                location: loan.booking.location, proposedReturn: clashes[loan.booking.id]?.proposedSlot?.start, dataClass: loan.dataClass
            )
        }
    }
}

/// User-facing feed failures. Feed fetch failures are shown as each source's health in
/// Settings instead. Messages live in the String Catalog.
enum FeedsFailure: Identifiable, Equatable {
    case invalidURL, keychain, read, save

    var id: Self { self }

    var message: LocalizedStringResource {
        switch self {
        case .invalidURL: "That doesn't look like a feed address. Paste the full https:// or webcal:// link."
        case .keychain: "Eagar could not use the Keychain for the feed address or token."
        case .read: "Eagar could not read your loans and Canvas items."
        case .save: "Eagar could not save the feed."
        }
    }
}
