import EagarAI
import EagarAITestSupport
import EagarCalendar
import EagarCore
import EagarStore
import EagarSuggest
import Foundation
import Testing
@testable import EagarBrief

/// M2 sections: trials about to bill, the monthly subscription summary and keep-in-touch
/// nudges (PRD M2 "Brief includes … trials about to bill and keep-in-touch suggestions").
struct BriefSourcesTests {
    private func trial(_ id: String, _ service: String, cancelDay: Int, window: Int = 7, dataClass: DataClass = .personal) -> BriefTrial {
        BriefTrial(
            id: id, service: service, price: Decimal(string: "9.99")!, currencyCode: "EUR",
            cancelBy: at(15, day: cancelDay), renewal: at(15, day: cancelDay + 2), windowDays: window, dataClass: dataClass
        )
    }

    private func nudge(_ id: String, _ title: String, day: Int, hour: Int, dataClass: DataClass) -> BriefNudge {
        BriefNudge(id: id, title: title, slot: DateInterval(start: at(hour, day: day), duration: 2 * 3600), dataClass: dataClass)
    }

    private func compose(now: Date = at(8), sources: BriefSources, preferences: BriefPreferences = .default) -> Brief {
        BriefComposer.compose(slot: morning, now: now, events: [], deadlines: [], sources: sources, preferences: preferences, calendar: dublin)
    }

    @Test func FR_TRIAL_02_trialsInsideTheirWindowAreAboutToBill() throws {
        let brief = compose(sources: BriefSources(trials: [
            trial("a", "Streamly", cancelDay: 14),        // today
            trial("b", "Cloudbox", cancelDay: 20),        // 6 days: inside 7
            trial("c", "Lingo", cancelDay: 22),           // 8 days: outside 7
            trial("d", "Gym", cancelDay: 16, window: 1),  // 2 days: outside its own 1-day window
            trial("e", "Old", cancelDay: 13),             // passed
        ]))
        let section = try #require(brief.sections.first { $0.kind == .trials })
        #expect(section.items.map(\.title) == ["Streamly", "Cloudbox"])
        #expect(section.items.allSatisfy { $0.kind == .trial && $0.isAllDay })
        #expect(section.items[0].actions == [.cancelSubscription, .confirmCancelled, .dismiss]) // FR-TRIAL-05
        #expect(section.items[0].detail?.hasPrefix("Cancel today") == true)
        #expect(section.items[1].detail?.hasPrefix("Cancel by") == true)
        #expect(section.items[0].id == "trial.a")
    }

    @Test func FR_TRIAL_06_summaryOnlyOnTheFirst() throws {
        let summary = BriefSubscriptionSummary(activeCount: 3, monthlyTotals: ["EUR": 30], chargeCount: 2, chargeTotals: ["EUR": 20], dataClass: .personal)
        let onFirst = compose(now: at(8, day: 1), sources: BriefSources(subscriptionSummary: summary))
        let item = try #require(onFirst.sections.first { $0.kind == .trials }?.items.first)
        #expect(item.kind == .subscriptionSummary)
        #expect(item.title == "Subscriptions this month")
        #expect(item.detail?.contains("3") == true)
        #expect(item.actions.contains(.open))
        #expect(compose(now: at(8, day: 2), sources: BriefSources(subscriptionSummary: summary)).sections.isEmpty)
    }

    @Test func summaryWithoutChargesSaysSo() {
        let summary = BriefSubscriptionSummary(activeCount: 1, monthlyTotals: ["EUR": 5], chargeCount: 0, chargeTotals: [:], dataClass: .personal)
        #expect(BriefComposer.summaryDetail(summary).contains("No charges"))
        #expect(BriefComposer.totalsText(["GBP": 5, "EUR": 10]).contains("£"))
    }

    @Test func FR_PEOPLE_05_nudgesAreKeepInTouchItemsWithTheirActions() throws {
        let brief = compose(sources: BriefSources(nudges: [
            nudge("nudge.2", "Saturday morning is free; Niamh: 5 weeks", day: 17, hour: 10, dataClass: .personal),
            nudge("nudge.1", "Thursday evening is free; Aoife: 7 weeks", day: 15, hour: 18, dataClass: .personal),
            nudge("nudge.0", "Gone", day: 13, hour: 18, dataClass: .personal),
        ]))
        let section = try #require(brief.sections.first { $0.kind == .keepInTouch })
        #expect(section.items.map(\.id) == ["nudge.1", "nudge.2"])
        #expect(section.items.allSatisfy { $0.actions == [.plan, .logContact, .snooze, .changeCadence] })
    }

    @Test func sectionsFollowTheDefaultOrderAndLimits() {
        let many = (0..<6).map { nudge("nudge.\($0)", "N\($0)", day: 15, hour: 9 + $0, dataClass: .personal) }
        let brief = compose(sources: BriefSources(trials: [trial("a", "Streamly", cancelDay: 15)], nudges: many))
        #expect(brief.sections.map(\.kind) == [.trials, .keepInTouch])
        #expect(brief.sections[1].items.count == 3)
        #expect(brief.sections[1].hiddenCount == 3)
    }

    /// A nudge in a slot after a college event is college: it keeps its class in the brief,
    /// and the notification and widget carry only counts for it (BD-04).
    @Test func Boundary_collegeNudgeIsCountsOnlyOutsideTheApp() throws {
        let brief = compose(sources: BriefSources(nudges: [
            nudge("nudge.c", "Tuesday afternoon is free; Ciara: 6 weeks", day: 14, hour: 14, dataClass: .college),
            nudge("nudge.p", "Friday evening is free; Darragh: 4 weeks", day: 16, hour: 18, dataClass: .personal),
        ]))
        let section = try #require(brief.sections.first { $0.kind == .keepInTouch })
        #expect(section.dataClass == .college)
        let content = BriefNotificationContent.make(for: brief)
        #expect(!content.body.contains("Ciara") && !content.title.contains("Ciara"))
        #expect(!content.body.contains("Darragh"))
        let widget = WidgetSnapshot.make(for: brief)
        #expect(widget.collegeCount == 1)
        #expect(!widget.lines.contains { $0.title.contains("Ciara") })
    }

    @Test func Boundary_B6_cloudPhrasingExcludesCollegeNudges() async throws {
        let providers = RecordingProvider.oneOfEach()
        let router = AIRouter(
            providers: providers, ledger: InMemoryLedger(),
            policy: StaticPolicySource(PolicySnapshot(consents: [ConsentKey(sourceID: nil, purpose: .briefPhrase, tier: .anthropicCloud): UUID()])),
            catalog: try ModelCatalog.bundled()
        )
        let brief = compose(sources: BriefSources(nudges: [
            nudge("nudge.c", "Tuesday afternoon is free; Ciara: 6 weeks", day: 14, hour: 14, dataClass: .college),
            nudge("nudge.p", "Friday evening is free; Darragh: 4 weeks", day: 16, hour: 18, dataClass: .personal),
        ]))
        _ = await BriefPhraser.phrase(brief, mode: .claudeForPersonal, router: router, calendar: dublin)
        let cloud = providers.filter { $0.locality.tier.leavesOwnerDevices }.flatMap(\.recordedCalls)
        #expect(!cloud.isEmpty) // the personal nudge did use Claude
        for call in cloud {
            let wire = String(decoding: call.wirePayload ?? Data(), as: UTF8.self)
            #expect(!wire.contains("Ciara"))
            #expect(call.payloads.allSatisfy { $0.dataClass != .college })
        }
    }

    @Test func newActionsMapToContentFreeLogKinds() {
        #expect(BriefSession.logKind(.cancelSubscription) == .itemOpened)
        #expect(BriefSession.logKind(.confirmCancelled) == .itemDone)
        #expect(BriefSession.logKind(.plan) == .itemDone)
        #expect(BriefSession.logKind(.logContact) == .itemDone)
        #expect(BriefSession.logKind(.changeCadence) == .itemRescheduled)
        #expect(!BriefAction.cancelSubscription.dealsWithItem)
        #expect(BriefAction.confirmCancelled.dealsWithItem)
    }

    @Test func phrasingLineCarriesTheDetail() {
        let item = BriefItem(id: "t", kind: .trial, title: "Streamly", start: at(0), isAllDay: true, dataClass: .personal, actions: [.dismiss], detail: "Cancel today")
        #expect(BriefPhraser.line(for: item, calendar: dublin) == "All day: Streamly: Cancel today")
        let summary = BriefItem(id: "s", kind: .subscriptionSummary, title: "Subscriptions", start: nil, dataClass: .personal, actions: [.open], detail: "Active: 3")
        #expect(BriefPhraser.line(for: summary, calendar: dublin) == "Subscriptions: Active: 3")
    }
}
