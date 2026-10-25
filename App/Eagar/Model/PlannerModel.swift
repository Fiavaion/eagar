import EagarAI
import EagarBrief
import EagarCalendar
import EagarCore
import EagarStore
import EagarSuggest
import Foundation
import Observation
import SwiftData

/// A deadline as the UI needs it: the snapshot plus its reminder-mirror state.
struct DeadlineRow: Sendable, Hashable, Identifiable {
    let snapshot: DeadlineSnapshot
    let mirrorListID: String?
    let mirroredReminderID: String?
    let completedAt: Date?
    var id: UUID { snapshot.id }
}

/// A deadline being added (`id == nil`) or edited.
struct DeadlineDraft: Equatable, Identifiable {
    var id: UUID?
    var title = ""
    var dueAt: Date
    var isAllDay = false
    var dataClass: DataClass = .personal
    var offsetsMinutes: Set<Int> = Set(defaultDeadlineOffsetsMinutes)
    var mirrorListID: String?
    var mirrorOverride = false

    init(dueAt: Date) {
        self.dueAt = dueAt
    }

    init(_ row: DeadlineRow) {
        id = row.id
        title = row.snapshot.title
        dueAt = row.snapshot.dueAt
        isAllDay = row.snapshot.isAllDay
        dataClass = row.snapshot.dataClass
        offsetsMinutes = Set(row.snapshot.reminderOffsetsMinutes)
        mirrorListID = row.mirrorListID
        mirrorOverride = row.snapshot.mirrorOverride
    }

    /// A snapshot for policy checks such as eligible reminder lists.
    var snapshot: DeadlineSnapshot {
        DeadlineSnapshot(title: title, dueAt: dueAt, isAllDay: isAllDay, dataClass: dataClass, mirrorOverride: mirrorOverride)
    }
}

/// A calendar's tag as the settings show it.
struct TagState: Equatable {
    let dataClass: DataClass
    let includeInBrief: Bool
    /// `false` while the tag is only Eagar's proposal.
    let confirmed: Bool
}

/// One line of the unified day timeline (FR-CAL-05; M1: events and deadlines). IDs are
/// prefixed `timeline.` so they never collide with brief item IDs in the same list.
struct TimelineItem: Identifiable, Hashable {
    enum Kind: Hashable { case event, deadline }

    let id: String
    let kind: Kind
    let title: String
    let start: Date
    let end: Date?
    let isAllDay: Bool
    let dataClass: DataClass
}

/// Calendars, deadlines and the Brief for M1 (FR-CAL, FR-DL, FR-BRIEF).
@MainActor
@Observable
final class PlannerModel {
    private(set) var access: CalendarAccess = .notDetermined
    private(set) var eventCalendars: [CalendarInfo] = []
    private(set) var reminderLists: [CalendarInfo] = []
    private(set) var tags: [String: CalendarTag] = [:]
    /// Today's events from every calendar, classified by tag.
    private(set) var todayEvents: [ClassifiedEvent] = []
    private(set) var deadlines: [DeadlineRow] = []
    private(set) var brief: Brief?
    /// Optional AI phrasing per section; empty until it arrives, or when off or failed.
    private(set) var phrasing: [BriefSectionKind: PhrasedSection] = [:]
    /// What Mark did with each brief item in this brief (not `open`).
    private(set) var itemStates: [String: BriefAction] = [:]
    private(set) var ratings: [String: Bool] = [:]
    var failure: PlannerFailure?

    var settings: BriefSettings {
        didSet {
            guard settings != oldValue else { return }
            settings.save(to: defaults)
            if settings.phrasingMode != oldValue.phrasingMode { phrasedSections = nil }
            composeBrief()
            if settings.slots != oldValue.slots { Task { await scheduleBriefNotifications() } }
        }
    }

    private let services: AppServices
    private let repository: DeadlineRepository
    private let defaults: UserDefaults
    private let clock: any EagarClock
    private let calendar: Calendar
    private let log = EagarLog(.app)
    private var session: BriefSession?
    private var sessionItemIDs: Set<String> = []
    private var phrasedSections: [BriefSection]?
    private var phrasingTask: Task<Void, Never>?

    static let notificationsRequestedKey = "notifications.authorisationRequested"

    init(services: AppServices, defaults: UserDefaults, clock: any EagarClock, calendar: Calendar) {
        self.services = services
        repository = DeadlineRepository(stores: services.stores)
        self.defaults = defaults
        self.clock = clock
        self.calendar = calendar
        settings = BriefSettings.load(from: defaults)
        access = services.eventStore.access(for: .event)
    }

    // MARK: Refresh

    /// Launch and scene activation: the app-open breakpoint (FR-BRIEF-02).
    func appBecameActive() async {
        await services.sync?.syncNow()
        await refresh()
        await scheduleBriefNotifications(appOpenedAt: clock.now())
    }

    func refresh() async {
        await loadCalendars()
        await loadDeadlines()
        composeBrief()
    }

    private var today: DateInterval { day(containing: clock.now()) }

    private func day(containing date: Date) -> DateInterval {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        return DateInterval(start: start, end: end)
    }

    // MARK: Calendars (FR-CAL-01, 02, 06)

    func loadCalendars() async {
        let store = services.eventStore
        access = store.access(for: .event)
        guard access == .fullAccess else {
            eventCalendars = []
            reminderLists = []
            todayEvents = []
            return
        }
        eventCalendars = store.calendars(for: .event).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        reminderLists = store.access(for: .reminder) == .fullAccess
            ? store.calendars(for: .reminder).sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
            : []
        do {
            tags = try await services.calendarTags.tags(for: eventCalendars + reminderLists)
        } catch {
            log.error("reading calendar tags failed: \(error)")
            failure = .calendarRead
        }
        todayEvents = await classifiedEvents(in: today)
    }

    private func classifiedEvents(in interval: DateInterval) async -> [ClassifiedEvent] {
        guard services.eventStore.access(for: .event) == .fullAccess else { return [] }
        do {
            let events = try await services.eventStore.events(in: interval, calendarIDs: nil)
            return CalendarClassifier.classify(events, tags: tags)
        } catch {
            log.error("reading events failed: \(error)")
            failure = .calendarRead
            return []
        }
    }

    func requestCalendarAccess() async {
        do {
            _ = try await services.eventStore.requestFullAccess()
        } catch {
            log.error("calendar access request failed: \(error)")
            failure = .calendarAccess
        }
        await refresh()
    }

    /// Mark's tag for a calendar, or Eagar's proposal when there is none yet.
    func tag(for calendar: CalendarInfo) -> TagState {
        if let tag = tags[calendar.id] {
            return TagState(dataClass: tag.dataClass, includeInBrief: tag.includeInBrief, confirmed: tag.confirmed)
        }
        return TagState(dataClass: services.calendarTags.proposedClass(for: calendar), includeInBrief: true, confirmed: false)
    }

    func setTag(_ calendar: CalendarInfo, dataClass: DataClass, includeInBrief: Bool) async {
        do {
            try await services.calendarTags.setTag(calendar, dataClass: dataClass, includeInBrief: includeInBrief)
        } catch {
            log.error("saving a calendar tag failed: \(error)")
            failure = .tagSave
        }
        await loadCalendars()
        composeBrief()
    }

    /// Confirms Eagar's proposals for every calendar and list Mark has not tagged (first run).
    func confirmProposedTags() async {
        for item in eventCalendars + reminderLists {
            let current = tag(for: item)
            guard !current.confirmed else { continue }
            do {
                try await services.calendarTags.setTag(item, dataClass: current.dataClass, includeInBrief: current.includeInBrief)
            } catch {
                log.error("saving a calendar tag failed: \(error)")
                failure = .tagSave
            }
        }
        await loadCalendars()
        composeBrief()
    }

    var isCollegeCalendarMissing: Bool {
        access == .fullAccess && CalendarDiagnosis.isCollegeCalendarMissing(eventCalendars)
    }

    /// Reminder lists Mark tagged college (FR-DL-03).
    var collegeListIDs: Set<String> {
        Set(reminderLists.filter { tag(for: $0).dataClass == .college }.map(\.id))
    }

    private func isIncludedInBrief(_ event: ClassifiedEvent) -> Bool {
        tags[event.event.calendarID]?.includeInBrief ?? true
    }

    /// Today's events and deadlines in time order, all-day items first (FR-CAL-05).
    var timeline: [TimelineItem] {
        let events = todayEvents.filter(isIncludedInBrief).map {
            TimelineItem(
                id: "timeline.event.\($0.id)", kind: .event, title: $0.event.title, start: $0.event.start,
                end: $0.event.end, isAllDay: $0.event.isAllDay, dataClass: $0.dataClass
            )
        }
        let due = deadlines.filter { $0.snapshot.status == .open && today.contains($0.snapshot.dueAt) }.map {
            TimelineItem(
                id: "timeline.deadline.\($0.id.uuidString)", kind: .deadline, title: $0.snapshot.title, start: $0.snapshot.dueAt,
                end: nil, isAllDay: $0.snapshot.isAllDay, dataClass: $0.snapshot.dataClass
            )
        }
        return (events + due).sorted { ($0.isAllDay ? 0 : 1, $0.start, $0.id) < ($1.isAllDay ? 0 : 1, $1.start, $1.id) }
    }

    func event(for item: BriefItem) -> ClassifiedEvent? {
        todayEvents.first { "event.\($0.id)" == item.id }
    }

    // MARK: Deadlines (FR-DL-01..04)

    func loadDeadlines() async {
        do {
            deadlines = try await repository.all()
                .sorted { ($0.snapshot.dueAt, $0.id.uuidString) < ($1.snapshot.dueAt, $1.id.uuidString) }
        } catch {
            log.error("reading deadlines failed: \(error)")
            failure = .deadlineRead
        }
    }

    var overdueDeadlines: [DeadlineRow] {
        let now = clock.now()
        return deadlines.filter { $0.snapshot.status == .open && $0.snapshot.dueAt < now }
    }

    var upcomingDeadlines: [DeadlineRow] {
        let now = clock.now()
        return deadlines.filter { $0.snapshot.status == .open && $0.snapshot.dueAt >= now }
    }

    var completedDeadlines: [DeadlineRow] {
        deadlines.filter { $0.snapshot.status == .done }
            .sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    func row(for id: UUID) -> DeadlineRow? { deadlines.first { $0.id == id } }

    func row(for item: BriefItem) -> DeadlineRow? {
        guard item.kind == .deadline else { return nil }
        let prefix = "deadline."
        return UUID(uuidString: String(item.id.dropFirst(prefix.count))).flatMap(row(for:))
    }

    func newDeadlineDraft() -> DeadlineDraft {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: clock.now()) ?? clock.now()
        return DeadlineDraft(dueAt: calendar.date(bySettingHour: 17, minute: 0, second: 0, of: tomorrow) ?? tomorrow)
    }

    /// Reminder lists a draft may mirror to (FR-DL-03).
    func eligibleReminderLists(for draft: DeadlineDraft) -> [CalendarInfo] {
        ReminderMirrorPolicy.eligibleLists(for: draft.snapshot, among: reminderLists, collegeListIDs: collegeListIDs)
    }

    /// Adds or updates a deadline, mirrors it if asked, and resyncs notifications. Returns
    /// whether the deadline was saved.
    @discardableResult
    func save(_ draft: DeadlineDraft) async -> Bool {
        let title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }
        let offsets = draft.offsetsMinutes.sorted(by: >)
        let id = draft.id ?? UUID()
        let existing = draft.id.flatMap(row(for:))
        do {
            if let existing, existing.snapshot.dataClass == draft.dataClass {
                let dueChanged = existing.snapshot.dueAt != draft.dueAt
                try await mutate(id, in: draft.dataClass) { deadline in
                    deadline.title = title
                    if dueChanged { deadline.reschedule(to: draft.dueAt) }
                    deadline.isAllDay = draft.isAllDay
                    deadline.reminderOffsetsMinutes = offsets
                    deadline.mirrorOverride = draft.mirrorOverride
                }
            } else {
                // New, or the class changed: the record moves to the store its class belongs in.
                if let existing { try await remove(id, in: existing.snapshot.dataClass) }
                let deadline = Deadline(
                    deadlineUUID: id, title: title, dueAt: draft.dueAt, isAllDay: draft.isAllDay,
                    reminderOffsetsMinutes: offsets, dataClass: draft.dataClass,
                    createdAt: clock.now()
                )
                deadline.mirrorOverride = draft.mirrorOverride
                if let existing, existing.snapshot.dueAt == draft.dueAt { deadline.snoozedUntil = existing.snapshot.snoozedUntil }
                try await services.stores.insert(deadline)
            }
        } catch {
            log.error("saving a deadline failed: \(error as? StoreError)")
            failure = .deadlineSave
            return false
        }
        await loadDeadlines()
        if let saved = row(for: id), mirrorNeedsUpdate(old: existing, new: saved, wantedList: draft.mirrorListID) {
            await updateMirror(saved, listID: draft.mirrorListID, previousReminderID: existing?.mirroredReminderID)
        }
        if let saved = row(for: id), existing == nil { services.donations.donateAddedDeadline(saved.snapshot) }
        await deadlinesChanged(requestAuthorisation: true)
        return true
    }

    private func mirrorNeedsUpdate(old: DeadlineRow?, new: DeadlineRow, wantedList: String?) -> Bool {
        guard let old else { return wantedList != nil }
        return wantedList != old.mirrorListID
            || (wantedList != nil && old.mirroredReminderID == nil)
            || (wantedList != nil && (old.snapshot.title != new.snapshot.title || old.snapshot.dueAt != new.snapshot.dueAt))
            || old.snapshot.dataClass != new.snapshot.dataClass
    }

    /// Replaces the mirrored reminder: removes the old one, then mirrors to `listID` if set.
    private func updateMirror(_ row: DeadlineRow, listID: String?, previousReminderID: String?) async {
        if let previousReminderID {
            do {
                try await services.eventStore.removeReminder(id: previousReminderID)
            } catch {
                log.error("removing a mirrored reminder failed: \(error)")
            }
        }
        var reminderID: String?
        if let listID, let list = reminderLists.first(where: { $0.id == listID }) {
            do {
                reminderID = try await ReminderMirror.mirror(row.snapshot, to: list, collegeListIDs: collegeListIDs, store: services.eventStore)
            } catch .crossBoundaryWrite {
                failure = .mirrorNotAllowed
            } catch {
                log.error("mirroring a deadline failed: \(error)")
                failure = .reminderMirror
            }
        }
        let savedID = reminderID
        let savedList = reminderID == nil ? nil : listID
        do {
            try await mutate(row.id, in: row.snapshot.dataClass) { deadline in
                deadline.mirroredReminderID = savedID
                deadline.mirrorListID = savedList
            }
        } catch {
            log.error("recording a reminder mirror failed: \(error as? StoreError)")
            failure = .deadlineSave
        }
        await loadDeadlines()
    }

    func markDone(_ id: UUID) async {
        let now = clock.now()
        await change(id) { $0.markDone(at: now) }
    }

    func snooze(_ id: UUID, until date: Date) async {
        await change(id) { $0.snooze(until: date) }
    }

    func reschedule(_ id: UUID, to date: Date) async {
        await change(id) { $0.reschedule(to: date) }
    }

    func delete(_ id: UUID) async {
        guard let existing = row(for: id) else { return }
        if let reminderID = existing.mirroredReminderID {
            do {
                try await services.eventStore.removeReminder(id: reminderID)
            } catch {
                log.error("removing a mirrored reminder failed: \(error)")
            }
        }
        do {
            try await remove(id, in: existing.snapshot.dataClass)
        } catch {
            log.error("deleting a deadline failed: \(error as? StoreError)")
            failure = .deadlineSave
        }
        await deadlinesChanged(requestAuthorisation: false)
    }

    /// Snooze choices (FR-DL-04): an hour from now, or tomorrow at 09:00.
    var snoozeInAnHour: Date { clock.now().addingTimeInterval(3600) }

    var snoozeTomorrowMorning: Date {
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: clock.now()) ?? clock.now()
        return calendar.date(bySettingHour: 9, minute: 0, second: 0, of: tomorrow) ?? tomorrow
    }

    private func change(_ id: UUID, _ body: @Sendable (Deadline) -> Void) async {
        guard let existing = row(for: id) else { return }
        do {
            try await mutate(id, in: existing.snapshot.dataClass, body)
        } catch {
            log.error("updating a deadline failed: \(error as? StoreError)")
            failure = .deadlineSave
        }
        await deadlinesChanged(requestAuthorisation: false)
    }

    private func mutate(_ id: UUID, in dataClass: DataClass, _ body: @Sendable (Deadline) -> Void) async throws {
        try await repository.update(id, in: dataClass, body)
    }

    private func remove(_ id: UUID, in dataClass: DataClass) async throws {
        try await repository.delete(id, in: dataClass)
    }

    /// After any deadline change: reload, resync notifications (FR-DL-02), recompose the brief.
    private func deadlinesChanged(requestAuthorisation: Bool) async {
        if requestAuthorisation && !defaults.bool(forKey: Self.notificationsRequestedKey) {
            await requestNotificationAuthorisation()
        }
        await loadDeadlines()
        await DeadlineNotificationSync.sync(
            deadlines: deadlines.map(\.snapshot), now: clock.now(), scheduler: services.deadlineNotifications, calendar: calendar
        )
        composeBrief()
        await scheduleBriefNotifications()
        await services.sync?.syncLocalChanges()
    }

    func requestNotificationAuthorisation() async {
        defaults.set(true, forKey: Self.notificationsRequestedKey)
        do {
            let granted = try await services.deadlineNotifications.requestAuthorization()
            log.notice("notification authorisation: \(granted)")
        } catch {
            log.error("notification authorisation request failed: \(error as? StoreError)")
        }
    }

    // MARK: The Brief (FR-BRIEF-01..08)

    /// The slot whose brief is current: the latest enabled slot already started today, else the
    /// first one. With every slot off, the in-app brief still shows as a morning brief.
    func currentSlot(at now: Date) -> BriefSlot {
        let slots = settings.enabledSlots
        return slots.last { $0.time(on: now, calendar: calendar) <= now } ?? slots.first ?? BriefSlot.defaultSlots[0]
    }

    private func briefDeadlines(at now: Date) -> [BriefDeadline] {
        deadlines
            .filter { $0.snapshot.status == .open && ($0.snapshot.snoozedUntil ?? .distantPast) <= now }
            .map { BriefDeadline(id: $0.id.uuidString, title: $0.snapshot.title, dueAt: $0.snapshot.dueAt, isAllDay: $0.snapshot.isAllDay, dataClass: $0.snapshot.dataClass) }
    }

    /// Deterministic assembly first (NFR-PERF-03); phrasing is started afterwards and never waited on.
    func composeBrief() {
        let now = clock.now()
        let composed = BriefComposer.compose(
            slot: currentSlot(at: now), now: now, events: todayEvents.filter(isIncludedInBrief),
            deadlines: briefDeadlines(at: now), preferences: settings.preferences, calendar: calendar
        )
        if composed.id != brief?.id {
            session = BriefSession(brief: composed, log: services.eventLog, clock: clock)
            sessionItemIDs = Set(composed.allItems.map(\.id))
            itemStates = [:]
            ratings = [:]
        }
        brief = composed
        services.widgets.publish(WidgetSnapshot.make(for: composed))
        startPhrasing(composed)
    }

    private func startPhrasing(_ brief: Brief) {
        let mode = settings.phrasingMode
        guard mode != .off else {
            phrasingTask?.cancel()
            phrasing = [:]
            phrasedSections = nil
            return
        }
        guard brief.sections != phrasedSections else { return }
        phrasedSections = brief.sections
        phrasing = [:]
        phrasingTask?.cancel()
        let router = services.router
        let calendar = calendar
        phrasingTask = Task { [weak self] in
            let result = await BriefPhraser.phrase(brief, mode: mode, router: router, calendar: calendar)
            guard !Task.isCancelled else { return }
            self?.phrasing = result
        }
    }

    /// Logs that the brief was opened (FR-BRIEF-08).
    func briefOpened() async {
        do {
            try await session?.opened()
        } catch {
            log.error("event log write failed: \(error)")
        }
    }

    /// Open and dismiss for any item, done for a deadline.
    func perform(_ action: BriefAction, on item: BriefItem) async {
        if action == .done, let row = row(for: item) { await markDone(row.id) }
        await record(action, on: item)
    }

    func snooze(_ item: BriefItem, until date: Date) async {
        if let row = row(for: item) { await snooze(row.id, until: date) }
        await record(.snooze, on: item)
    }

    func reschedule(_ item: BriefItem, to date: Date) async {
        if let row = row(for: item) { await reschedule(row.id, to: date) }
        await record(.reschedule, on: item)
    }

    func rate(_ item: BriefItem, helpful: Bool) async {
        ratings[item.id] = helpful
        do {
            if sessionItemIDs.contains(item.id), let session {
                try await session.rated(item.id, helpful: helpful)
            } else {
                try await services.eventLog.record(helpful ? .thumbsUp : .thumbsDown, subject: item.id, dataClass: item.dataClass)
            }
        } catch {
            log.error("event log write failed: \(error)")
        }
    }

    private func record(_ action: BriefAction, on item: BriefItem) async {
        if action != .open { itemStates[item.id] = action }
        do {
            if sessionItemIDs.contains(item.id), let session {
                try await session.acted(action, on: item.id)
            } else {
                // Added after the brief was opened: logged directly, outside the session timing.
                try await services.eventLog.record(Self.logKind(action), subject: item.id, dataClass: item.dataClass)
            }
        } catch {
            log.error("event log write failed: \(error)")
        }
    }

    private static func logKind(_ action: BriefAction) -> EventLogKind {
        switch action {
        case .open: .itemOpened
        case .done: .itemDone
        case .snooze: .itemSnoozed
        case .reschedule: .itemRescheduled
        case .dismiss: .itemDismissed
        }
    }

    // MARK: Delivery (FR-BRIEF-02, FR-BRIEF-05)

    /// Schedules one notification per enabled slot at its delivery time: the first breakpoint at
    /// or after the slot, at most 45 minutes late. A slot whose delivery time has passed today,
    /// or which the app being open has delivered, is scheduled for tomorrow. Replaces stale
    /// requests. The content is counts only.
    func scheduleBriefNotifications(appOpenedAt: Date? = nil) async {
        let now = clock.now()
        let scheduler = services.briefNotifications
        var wanted: Set<String> = []
        for slot in settings.enabledSlots {
            for offset in 0...1 {
                guard let date = calendar.date(byAdding: .day, value: offset, to: now) else { continue }
                let interval = day(containing: date)
                let slotTime = slot.time(on: interval.start, calendar: calendar)
                let events = offset == 0 ? todayEvents : await classifiedEvents(in: interval)
                let breakpoints = AvailabilityEngine.breakpoints(for: events, in: interval, calendar: calendar).map(\.date)
                let time = BriefDelivery.deliveryTime(slotTime: slotTime, breakpoints: breakpoints, appOpenedAt: offset == 0 ? appOpenedAt : nil)
                guard time > now else { continue }
                let brief = BriefComposer.compose(
                    slot: slot, now: time, events: events.filter(isIncludedInBrief),
                    deadlines: briefDeadlines(at: time), preferences: settings.preferences, calendar: calendar
                )
                let identifier = BriefNotificationID.make(slot: slot.kind, day: interval.start, calendar: calendar)
                do {
                    try await scheduler.schedule(BriefNotificationContent.make(for: brief), at: time, identifier: identifier)
                    wanted.insert(identifier)
                } catch {
                    log.error("scheduling the brief notification failed")
                }
                break
            }
        }
        let stale = await scheduler.pendingBriefIdentifiers().filter { !wanted.contains($0) }
        if !stale.isEmpty { await scheduler.remove(identifiers: stale.sorted()) }
    }
}

/// User-facing planner failures. Messages live in the String Catalog.
enum PlannerFailure: Identifiable, Equatable {
    case calendarAccess, calendarRead, tagSave, deadlineRead, deadlineSave, reminderMirror, mirrorNotAllowed

    var id: Self { self }

    var message: LocalizedStringResource {
        switch self {
        case .calendarAccess: "Eagar could not ask for calendar access."
        case .calendarRead: "Eagar could not read your calendars."
        case .tagSave: "Eagar could not save the calendar tag."
        case .deadlineRead: "Eagar could not read your deadlines."
        case .deadlineSave: "Eagar could not save the deadline."
        case .reminderMirror: "Eagar could not add the reminder."
        case .mirrorNotAllowed: "A college deadline can only be mirrored to a college or local reminder list."
        }
    }
}
