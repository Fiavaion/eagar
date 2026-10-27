import EagarBrief
import EagarCalendar
import EagarCore
import EagarMoney
import Foundation
import Observation

/// A trial being added (`id == nil`), edited or confirmed from an import (FR-TRIAL-01, 03).
struct TrialEditorDraft: Equatable, Identifiable {
    /// Where a proposed trial came from, for the confirmation banner.
    enum Origin: Equatable {
        case manual
        /// In-app screenshot or file import.
        case screenshot(TrialExtractionMethod)
        /// The share extension; `pendingID` names the hand-over file to remove afterwards.
        case shared(pendingID: UUID, method: TrialExtractionMethod)
    }

    var id: UUID?
    var service = ""
    var price: Decimal = 0
    var currencyCode = defaultTrialCurrencyCode
    var period: BillingPeriod = .monthly
    var isTrial = true
    var startedAt: Date
    var renewsAt: Date
    var cancelURLString = ""
    var safetyMarginDays = defaultTrialSafetyMarginDays
    var reminderDays: Set<Int> = Set(defaultTrialReminderDays)
    var origin: Origin = .manual
    /// Sheet identity: a new draft gets its own, an edit uses the trial's.
    let sheetID: UUID

    var isNew: Bool { id == nil }
    var isProposed: Bool { origin != .manual }

    init(startedAt: Date, renewsAt: Date) {
        self.startedAt = startedAt
        self.renewsAt = renewsAt
        sheetID = UUID()
    }

    init(_ trial: TrialSnapshot, now: Date) {
        id = trial.id
        service = trial.service
        price = trial.price
        currencyCode = trial.currencyCode
        period = trial.period
        isTrial = trial.isTrial
        startedAt = trial.startedAt ?? now
        renewsAt = trial.renewsAt
        cancelURLString = trial.cancelURL?.absoluteString ?? ""
        safetyMarginDays = trial.safetyMarginDays
        reminderDays = Set(trial.reminderDays)
        sheetID = trial.id
    }

    /// A proposed trial from an import, with defaults for whatever extraction missed.
    init(_ draft: TrialDraft, origin: Origin, now: Date, calendar: Calendar) {
        let fallback = calendar.date(byAdding: .day, value: 7, to: calendar.startOfDay(for: now)) ?? now
        self.init(startedAt: now, renewsAt: draft.renewsAt ?? fallback)
        service = draft.service ?? ""
        price = draft.price ?? 0
        currencyCode = draft.currencyCode ?? defaultTrialCurrencyCode
        period = draft.period ?? .monthly
        isTrial = draft.isTrial
        cancelURLString = draft.cancelURL?.absoluteString ?? ""
        self.origin = origin
    }

    var trimmedService: String { service.trimmingCharacters(in: .whitespacesAndNewlines) }
    var canSave: Bool { !trimmedService.isEmpty && price >= 0 }

    /// A cancel URL Eagar will open: only `https`/`http` with a host (FR-TRIAL-05).
    var cancelURL: URL? {
        let trimmed = cancelURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: withScheme), let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http", url.host() != nil
        else { return nil }
        return url
    }

    /// The snapshot to store. Trials are personal: Mark enters or imports them himself.
    func snapshot(status: TrialStatus = .active, cancelledAt: Date? = nil) -> TrialSnapshot {
        TrialSnapshot(
            id: id ?? sheetID, service: trimmedService, price: price, currencyCode: currencyCode, period: period,
            isTrial: isTrial, startedAt: startedAt, renewsAt: renewsAt, cancelURL: cancelURL, status: status,
            safetyMarginDays: max(0, safetyMarginDays), reminderDays: reminderDays.sorted(by: >), dataClass: .personal,
            cancelledAt: cancelledAt
        )
    }

    func cancelBy(calendar: Calendar) -> Date {
        TrialSchedule.cancelBy(renewal: renewsAt, safetyMarginDays: safetyMarginDays, calendar: calendar)
    }
}

/// Trials and subscriptions (FR-TRIAL-01, 02, 03, 05, 06): the list, reminders, the cancel
/// flow, imports and what the brief and the deadlines list need.
@MainActor
@Observable
final class MoneyModel {
    private(set) var trials: [TrialSnapshot] = []
    /// A proposed trial waiting for Mark's confirmation (screenshot or share extension).
    var review: TrialEditorDraft?
    /// True while a screenshot is being read.
    private(set) var isImporting = false
    var failure: MoneyFailure?
    /// Called after any change, so the brief and deadlines refresh.
    var onChange: (() -> Void)?

    private let services: AppServices
    private let repository: TrialRepository
    private let reader: any TrialReading
    private let clock: any EagarClock
    private let calendar: Calendar
    private let log = EagarLog(.money)

    /// `reader` defaults to PersonalStore; tests pass one that fails.
    init(services: AppServices, clock: any EagarClock, calendar: Calendar, reader: (any TrialReading)? = nil) {
        self.services = services
        let repository = TrialRepository(stores: services.stores)
        self.repository = repository
        self.reader = reader ?? repository
        self.clock = clock
        self.calendar = calendar
    }

    var now: Date { clock.now() }

    var activeTrials: [TrialSnapshot] {
        trials.filter { $0.status == .active }
            .sorted { (nextCancelBy($0) ?? .distantFuture, $0.service) < (nextCancelBy($1) ?? .distantFuture, $1.service) }
    }

    var cancelledTrials: [TrialSnapshot] {
        trials.filter { $0.status == .cancelled }.sorted { ($0.cancelledAt ?? .distantPast) > ($1.cancelledAt ?? .distantPast) }
    }

    func trial(_ id: UUID) -> TrialSnapshot? { trials.first { $0.id == id } }

    func nextCancelBy(_ trial: TrialSnapshot) -> Date? { trial.nextCancelBy(now: now, calendar: calendar)?.cancelBy }

    func nextRenewal(_ trial: TrialSnapshot) -> Date? { trial.nextCancelBy(now: now, calendar: calendar)?.renewal }

    /// This month's summary (FR-TRIAL-06).
    var summary: MonthlySubscriptionSummary { SubscriptionSummary.summary(trials, monthContaining: now, calendar: calendar) }

    // MARK: Loading

    /// Launch and activation: reload, reconcile reminders, pick up share-extension imports.
    /// After a failed read the pending reminders are kept.
    func refresh() async {
        if await load() { await reconcileReminders() }
        checkPendingImports()
    }

    /// Returns false when the read failed; the list keeps its last value and `failure` is set.
    @discardableResult
    func load() async -> Bool {
        do {
            trials = try await reader.all()
            return true
        } catch {
            log.error("reading trials failed: \(error)")
            failure = .read
            return false
        }
    }

    /// Removes stale reminders and schedules every planned one (FR-TRIAL-02). Only after a
    /// successful read: an empty list from a failed one would remove every reminder.
    private func reconcileReminders() async {
        await TrialReminderSync.sync(trials: trials, now: now, scheduler: services.trialReminders, calendar: calendar)
    }

    // MARK: Editing (FR-TRIAL-01)

    func newDraft() -> TrialEditorDraft {
        let today = calendar.startOfDay(for: now)
        let renewal = calendar.date(byAdding: .day, value: 7, to: today) ?? today
        return TrialEditorDraft(startedAt: today, renewsAt: renewal)
    }

    func editDraft(_ id: UUID) -> TrialEditorDraft? { trial(id).map { TrialEditorDraft($0, now: now) } }

    /// Adds or updates a trial (logical uniqueness via `TrialUpsert`), then reconciles its
    /// reminders. Returns whether it was saved.
    @discardableResult
    func save(_ draft: TrialEditorDraft) async -> Bool {
        guard draft.canSave else { return false }
        let existing = draft.id.flatMap(trial)
        let snapshot = draft.snapshot(status: existing?.status ?? .active, cancelledAt: existing?.cancelledAt)
        do {
            try await repository.upsert(snapshot, now: now, calendar: calendar)
        } catch {
            log.error("saving a trial failed: \(StoreFailureKind(error))")
            failure = .save
            return false
        }
        if case let .shared(pendingID, _) = draft.origin { services.pendingImports.remove(id: pendingID) }
        await changed()
        return true
    }

    func delete(_ id: UUID) async {
        do {
            try await repository.delete(id)
        } catch {
            log.error("deleting a trial failed: \(StoreFailureKind(error))")
            failure = .save
        }
        await changed()
    }

    // MARK: Cancelling (FR-TRIAL-05)

    /// The service's cancel page, or Apple's subscriptions page.
    func cancelTarget(_ id: UUID) -> URL {
        trial(id).map(TrialCancelAction.target(for:)) ?? TrialCancelAction.appStoreSubscriptionsURL
    }

    /// Records Mark's confirmation that he cancelled. Opening the cancel page never does.
    func confirmCancelled(_ id: UUID) async {
        let date = now
        await mutate(id) { $0.confirmCancelled(at: date) }
    }

    func reactivate(_ id: UUID) async {
        await mutate(id) { $0.reactivate() }
    }

    /// A trial notification's "I've cancelled" action. The app may have been launched in the
    /// background for it, so trials are loaded first if needed.
    func handleConfirmCancelledAction(trialID: UUID) async {
        if trial(trialID) == nil { await load() }
        await confirmCancelled(trialID)
    }

    private func mutate(_ id: UUID, _ body: @Sendable (Trial) -> Void) async {
        do {
            try await repository.update(id, body)
        } catch {
            log.error("updating a trial failed: \(StoreFailureKind(error))")
            failure = .save
        }
        await changed()
    }

    private func changed() async {
        if await load() { await reconcileReminders() }
        onChange?()
        await services.sync?.syncLocalChanges()
    }

    // MARK: Imports (FR-TRIAL-03)

    /// Reads a screenshot on device: Vision OCR, then the on-device model through the router
    /// (parser fallback). Shows the proposal for confirmation; nothing is stored yet.
    func importImage(_ data: Data) async {
        isImporting = true
        defer { isImporting = false }
        let importer = TrialScreenshotImporter(router: services.router, mode: .onDeviceModel, calendar: calendar)
        do {
            let result = try await importer.importTrial(fromImageData: data)
            review = TrialEditorDraft(result.draft, origin: .screenshot(result.method), now: now, calendar: calendar)
        } catch .noText {
            failure = .importNoText
        } catch {
            log.notice("trial import failed: \(error)")
            failure = .importFailed
        }
    }

    /// Shows the oldest share-extension import for confirmation, if any and nothing else is
    /// being reviewed.
    func checkPendingImports() {
        guard review == nil, let next = services.pendingImports.all().first else { return }
        review = TrialEditorDraft(next.draft, origin: .shared(pendingID: next.id, method: next.method), now: now, calendar: calendar)
    }

    /// Mark discarded a proposal: the hand-over file goes, nothing is stored.
    func discardReview(_ draft: TrialEditorDraft) {
        if case let .shared(pendingID, _) = draft.origin { services.pendingImports.remove(id: pendingID) }
        review = nil
        checkPendingImports()
    }

    // MARK: Brief and deadlines

    /// Active trials' cancel-by as deadlines with origin `trial` (FR-DL-01). They are shown,
    /// never stored: the reminders come from the trial plan only, so nothing notifies twice.
    var deadlineRows: [DeadlineRow] {
        trials.filter { $0.status == .active }.compactMap { trial in
            TrialDeadlineMapping.snapshot(for: trial, now: now, calendar: calendar).map {
                DeadlineRow(snapshot: $0, mirrorListID: nil, mirroredReminderID: nil, completedAt: nil)
            }
        }
    }

    /// Active trials for the brief's "about to bill" section, windowed by their reminder days.
    var briefTrials: [BriefTrial] {
        trials.compactMap { trial in
            guard let target = trial.nextCancelBy(now: now, calendar: calendar) else { return nil }
            return BriefTrial(
                id: trial.id.uuidString, service: trial.service, price: trial.price, currencyCode: trial.currencyCode,
                cancelBy: target.cancelBy, renewal: target.renewal, windowDays: trial.reminderDays.max() ?? 7,
                dataClass: trial.dataClass
            )
        }
    }

    /// The monthly summary for the brief on the 1st, when anything is active (FR-TRIAL-06).
    var briefSummary: BriefSubscriptionSummary? {
        let summary = summary
        guard summary.activeCount > 0 else { return nil }
        return BriefSubscriptionSummary(
            activeCount: summary.activeCount, monthlyTotals: summary.monthlyTotals,
            chargeCount: summary.upcomingCharges.count, chargeTotals: summary.upcomingTotals, dataClass: summary.dataClass
        )
    }
}

/// User-facing trial failures. Messages live in the String Catalog.
enum MoneyFailure: Identifiable, Equatable {
    case read, save, importNoText, importFailed

    var id: Self { self }

    var message: LocalizedStringResource {
        switch self {
        case .read: "Eagar could not read your subscriptions."
        case .save: "Eagar could not save the subscription."
        case .importNoText: "Eagar found no text in that image. Try a clearer screenshot of the receipt or confirmation."
        case .importFailed: "Eagar could not read that image."
        }
    }
}
