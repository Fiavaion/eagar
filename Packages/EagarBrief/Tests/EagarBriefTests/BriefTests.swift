import EagarAI
import EagarAITestSupport
import EagarCalendar
import EagarCore
import EagarStore
import EagarSuggest
import Foundation
import Testing
@testable import EagarBrief

let dublin: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Dublin")!
    return calendar
}()

func at(_ hour: Int, _ minute: Int = 0, day: Int = 14) -> Date {
    dublin.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

func event(_ id: String, _ title: String, _ start: Date, _ minutes: Int, _ dataClass: DataClass, allDay: Bool = false) -> ClassifiedEvent {
    ClassifiedEvent(event: CalendarEvent(id: id, calendarID: dataClass == .college ? "ncad" : "home", title: title, start: start, end: start + TimeInterval(minutes * 60), isAllDay: allDay), dataClass: dataClass)
}

let morning = BriefSlot(kind: .morning, hour: 8)

/// A fixture day: one college meeting, one personal appointment, a college deadline overdue,
/// a personal deadline upcoming.
func fixtureBrief(now: Date = at(8)) -> Brief {
    BriefComposer.compose(
        slot: morning, now: now,
        events: [
            event("e1", "Studio crit with Year 3", at(10), 60, .college),
            event("e2", "Dentist", at(13), 30, .personal),
            event("e3", "Bank holiday", at(0), 24 * 60, .personal, allDay: true),
        ],
        deadlines: [
            BriefDeadline(id: "d1", title: "Submit module descriptors", dueAt: at(9, day: 13), dataClass: .college),
            BriefDeadline(id: "d2", title: "Renew car tax", dueAt: at(17, day: 16), dataClass: .personal),
        ],
        calendar: dublin
    )
}

struct BriefComposerTests {
    @Test func sectionsOrderAndContent() {
        let brief = fixtureBrief()
        #expect(brief.sections.map(\.kind) == [.overdue, .today, .deadlines])
        #expect(brief.sections[0].items.map(\.title) == ["Submit module descriptors"])
        #expect(brief.sections[1].items.map(\.title) == ["Bank holiday", "Studio crit with Year 3", "Dentist"]) // all-day first
        #expect(brief.sections[2].items.map(\.title) == ["Renew car tax"])
        #expect(brief.allItems.allSatisfy { !$0.actions.isEmpty }) // FR-BRIEF-03
        #expect(brief.sections[0].items[0].actions == [.done, .snooze, .reschedule]) // FR-DL-04
        #expect(brief.sections[1].dataClass == .college)
    }

    @Test func pastEventsAreLeftOut() {
        let brief = fixtureBrief(now: at(12))
        #expect(brief.sections.first { $0.kind == .today }?.items.map(\.title) == ["Bank holiday", "Dentist"])
    }

    @Test func steeringHidesReordersAndLimits() {
        let prefs = BriefPreferences(order: [.deadlines, .today, .overdue], hidden: [.deadlines], maxItems: [.today: 1])
        let brief = BriefComposer.compose(slot: morning, now: at(8), events: [
            event("e1", "A", at(10), 30, .personal), event("e2", "B", at(11), 30, .personal),
        ], deadlines: [BriefDeadline(id: "x", title: "Late", dueAt: at(7), dataClass: .personal), BriefDeadline(id: "y", title: "Soon", dueAt: at(20), dataClass: .personal)], preferences: prefs, calendar: dublin)
        #expect(brief.sections.map(\.kind) == [.overdue, .today]) // overdue forced first; deadlines hidden
        #expect(brief.sections[1].items.map(\.title) == ["A"])
        #expect(brief.sections[1].hiddenCount == 1)
    }

    @Test func emptyBrief() {
        let brief = BriefComposer.compose(slot: morning, now: at(8), events: [], deadlines: [], calendar: dublin)
        #expect(brief.isEmpty)
        #expect(BriefNotificationContent.make(for: brief).body == "Nothing needs you right now.")
    }

    /// NFR-PERF-03: deterministic assembly well under 300 ms for a heavy day.
    @Test func assemblyIsFast() {
        let events = (0..<500).map { event("e\($0)", "Event \($0)", at(8) + TimeInterval($0 * 60), 30, $0 % 3 == 0 ? .college : .personal) }
        let deadlines = (0..<500).map { BriefDeadline(id: "d\($0)", title: "D\($0)", dueAt: at(8) + TimeInterval($0 * 600), dataClass: .personal) }
        let start = ContinuousClock.now
        _ = BriefComposer.compose(slot: morning, now: at(8), events: events, deadlines: deadlines, calendar: dublin)
        #expect(ContinuousClock.now - start < .milliseconds(300))
    }
}

struct BriefDeliveryTests {
    /// M1 acceptance: the morning brief fires at the first breakpoint after the slot time (or at
    /// app open), never later than 45 minutes after the slot (simulated clock).
    @Test func firstBreakpointAfterSlot() {
        let slot = at(8)
        #expect(BriefDelivery.deliveryTime(slotTime: slot, breakpoints: [at(7, 30), at(8, 20), at(8, 40)]) == at(8, 20))
        #expect(BriefDelivery.deliveryTime(slotTime: slot, breakpoints: [at(8)]) == at(8))
    }

    @Test func appOpenCountsAsBreakpoint() {
        #expect(BriefDelivery.deliveryTime(slotTime: at(8), breakpoints: [at(8, 40)], appOpenedAt: at(8, 5)) == at(8, 5))
        #expect(BriefDelivery.deliveryTime(slotTime: at(8), breakpoints: [], appOpenedAt: at(7, 50)) == at(8, 45))
    }

    @Test(arguments: [[], [at(9)], [at(8, 46)], [at(7)]])
    func neverLaterThan45Minutes(breakpoints: [Date]) {
        let delivery = BriefDelivery.deliveryTime(slotTime: at(8), breakpoints: breakpoints)
        #expect(delivery <= at(8, 45))
        #expect(delivery >= at(8))
    }

    @Test func isDue() {
        #expect(!BriefDelivery.isDue(now: at(8, 10), slotTime: at(8), breakpoints: [at(8, 20)], appOpenedAt: nil, alreadyDelivered: false))
        #expect(BriefDelivery.isDue(now: at(8, 20), slotTime: at(8), breakpoints: [at(8, 20)], appOpenedAt: nil, alreadyDelivered: false))
        #expect(!BriefDelivery.isDue(now: at(9), slotTime: at(8), breakpoints: [], appOpenedAt: nil, alreadyDelivered: true))
    }
}

struct BriefEgressTests {
    /// M1 acceptance: college events appear as content in the app, but only as counts in the
    /// notification and the widget.
    @Test func Boundary_collegeItemsAreCountsOnlyInNotificationAndWidget() {
        let brief = fixtureBrief()
        let collegeTitles = brief.allItems.filter { $0.dataClass == .college }.map(\.title)
        #expect(collegeTitles.count == 2) // shown in-app

        let notification = BriefNotificationContent.make(for: brief)
        for title in collegeTitles {
            #expect(!notification.title.contains(title) && !notification.body.contains(title))
        }
        #expect(notification.body == "Items to look at: 5, including college items: 2")
        #expect(notification.level == .active) // there is an overdue item

        let widget = BriefWidgetSnapshot.make(for: brief)
        #expect(widget.collegeCount == 2)
        let encoded = String(decoding: try! JSONEncoder().encode(widget), as: UTF8.self)
        for title in collegeTitles { #expect(!encoded.contains(title)) }
        #expect(widget.lines.compactMap(\.title) == ["Bank holiday", "Dentist", "Renew car tax"])
    }

    @Test func notificationTitles() {
        let brief = BriefComposer.compose(slot: BriefSlot(kind: .endOfDay, hour: 17), now: at(17), events: [event("e", "Gym", at(18), 60, .personal)], deadlines: [], calendar: dublin)
        let content = BriefNotificationContent.make(for: brief)
        #expect(content.title == "Your end-of-day brief")
        #expect(content.body == "Items to look at: 1")
        #expect(content.level == .passive)
    }
}

private let catalog = try! ModelCatalog.bundled()

struct BriefPhrasingTests {
    /// B-6: with a cloud provider enabled and consent given, brief phrasing sends only
    /// personal/public lines to Claude; no field derived from a college item is in any cloud payload.
    @Test func Boundary_B6_cloudPhrasingExcludesCollegeItems() async throws {
        let providers = RecordingProvider.oneOfEach()
        let router = AIRouter(
            providers: providers, ledger: InMemoryLedger(),
            policy: StaticPolicySource(PolicySnapshot(consents: [ConsentKey(sourceID: nil, purpose: .briefPhrase, tier: .anthropicCloud): UUID()])),
            catalog: catalog
        )
        let brief = fixtureBrief()
        let phrased = await BriefPhraser.phrase(brief, mode: .claudeForPersonal, router: router, calendar: dublin)

        let collegeTitles = brief.allItems.filter { $0.dataClass == .college }.map(\.title)
        let cloud = providers.filter { $0.locality.tier == .anthropicCloud }.flatMap(\.recordedCalls)
        #expect(!cloud.isEmpty) // personal lines did use Claude
        for call in cloud {
            #expect(call.effectiveClass != .college)
            let wire = String(decoding: call.wirePayload ?? Data(), as: UTF8.self)
            for title in collegeTitles { #expect(!wire.contains(title)) }
            #expect(call.payloads.allSatisfy { $0.dataClass != .college })
        }
        // College lines were phrased, but only on a local tier.
        let collegeParts = phrased.values.flatMap(\.parts).filter(\.isCollege)
        #expect(!collegeParts.isEmpty)
        #expect(collegeParts.allSatisfy { $0.tier == .onDevice || $0.tier == .macLocal })
        for provider in providers where provider.locality.tier.leavesOwnerDevices {
            for call in provider.recordedCalls { #expect(call.payloads.allSatisfy { $0.dataClass != .college }) }
        }
    }

    @Test func offAndLocalOnlyModes() async throws {
        let providers = RecordingProvider.oneOfEach()
        let router = AIRouter(providers: providers, ledger: InMemoryLedger(), policy: StaticPolicySource(PolicySnapshot()), catalog: catalog)
        #expect(await BriefPhraser.phrase(fixtureBrief(), mode: .off, router: router).isEmpty)
        let local = await BriefPhraser.phrase(fixtureBrief(), mode: .localOnly, router: router, calendar: dublin)
        #expect(!local.isEmpty)
        #expect(providers.filter { $0.locality.tier.leavesOwnerDevices }.allSatisfy { $0.recordedCalls.isEmpty })
    }

    @Test func withoutConsentPersonalPhrasingIsBlockedNotLeaked() async throws {
        let providers = RecordingProvider.oneOfEach()
        let ledger = InMemoryLedger()
        let router = AIRouter(providers: providers, ledger: ledger, policy: StaticPolicySource(PolicySnapshot()), catalog: catalog)
        _ = await BriefPhraser.phrase(fixtureBrief(), mode: .claudeForPersonal, router: router, calendar: dublin)
        #expect(providers.first { $0.locality.tier == .anthropicCloud }?.recordedCalls.isEmpty == true)
        #expect(ledger.entries.contains { $0.draft.kind == .blocked && $0.draft.detail == "consentRequired" })
    }

    @Test func lineFormatting() {
        let item = BriefItem(id: "i", kind: .event, title: "Dentist", start: at(13), dataClass: .personal, actions: [.open])
        #expect(BriefPhraser.line(for: item, calendar: dublin).hasSuffix("Dentist"))
        #expect(BriefPhraser.line(for: item, calendar: dublin) != "Dentist")
        let allDay = BriefItem(id: "j", kind: .event, title: "Holiday", start: at(0), isAllDay: true, dataClass: .personal, actions: [.open])
        #expect(BriefPhraser.line(for: allDay, calendar: dublin) == "Holiday")
    }
}

struct FixedClock: EagarClock {
    let date: Date
    func now() -> Date { date }
}

final class MovingClock: EagarClock, @unchecked Sendable {
    // SAFETY: test-only; accessed from one test at a time.
    var current: Date
    init(_ date: Date) { current = date }
    func now() -> Date { current }
}

struct BriefSessionTests {
    /// FR-BRIEF-08 / SM2: opened → fully actioned time is logged; content-free.
    @Test func completionTimeIsLogged() async throws {
        let stores = try EagarStores(location: .inMemory, models: [EventLogEntry.self])
        let clock = MovingClock(at(8, 20))
        let log = EventLog(stores: stores, clock: clock)
        let brief = fixtureBrief()
        let session = BriefSession(brief: brief, log: log, clock: clock)
        try await session.opened()

        var completed = false
        for (index, item) in brief.allItems.enumerated() {
            clock.current = at(8, 21) + TimeInterval(index * 10)
            try await session.acted(.open, on: item.id) // opening alone doesn't count
            completed = try await session.acted(index.isMultiple(of: 2) ? .done : .dismiss, on: item.id)
        }
        #expect(completed)
        try await session.rated(brief.allItems[0].id, helpful: true)
        let records = try await log.records()
        let done = try #require(records.first { $0.kind == .briefCompleted })
        #expect(done.value == Double(60 + 4 * 10)) // 08:20 → 08:21:40
        #expect(done.dataClass == .college) // the brief contains college items
        #expect(records.filter { $0.kind == .briefOpened }.count == 1)
        #expect(records.contains { $0.kind == .thumbsUp })
        #expect(records.allSatisfy { !brief.allItems.map(\.title).contains($0.subjectRef) }) // no titles logged
    }
}
