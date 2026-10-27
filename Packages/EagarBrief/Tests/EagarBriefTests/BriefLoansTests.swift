import EagarAI
import EagarAITestSupport
import EagarCore
import Foundation
import Testing
@testable import EagarBrief

/// M2 "Brief includes loans due" (FR-BOOK-03, FR-BOOK-04) and the boundary for loan lines.
struct BriefLoansTests {
    private func loan(_ id: String, _ title: String, due: Date, deadline: String? = nil, location: String? = nil, proposed: Date? = nil) -> BriefLoan {
        BriefLoan(id: id, deadlineID: deadline, title: title, dueAt: due, location: location, proposedReturn: proposed)
    }

    private func deadline(_ id: String, _ title: String, due: Date) -> BriefDeadline {
        BriefDeadline(id: id, title: title, dueAt: due, dataClass: .college)
    }

    private func compose(now: Date = at(8), deadlines: [BriefDeadline] = [], loans: [BriefLoan]) -> Brief {
        BriefComposer.compose(slot: morning, now: now, events: [], deadlines: deadlines, sources: BriefSources(loans: loans), calendar: dublin)
    }

    @Test func FR_BOOK_03_loansDueAreTheirOwnSection() throws {
        let brief = compose(loans: [
            loan("b2", "Tripod and lights", due: at(12, day: 15), location: "Media loans desk"),
            loan("b1", "Camera kit", due: at(17)),
            loan("b3", "Projector", due: at(12, day: 25)), // beyond the 7-day horizon
        ])
        let section = try #require(brief.sections.first { $0.kind == .loans })
        #expect(section.items.map(\.title) == ["Camera kit", "Tripod and lights"])
        #expect(section.items.allSatisfy { $0.kind == .loan && $0.dataClass == .college })
        #expect(section.items[1].detail == "Return to Media loans desk")
        #expect(section.items[0].actions == [.done, .open])
        #expect(section.items[0].id == "loan.b1")
    }

    @Test func overdueLoanSaysSoAndCanBeSnoozed() throws {
        let brief = compose(loans: [loan("b1", "Camera kit", due: at(7))])
        let item = try #require(brief.sections.first { $0.kind == .loans }?.items.first)
        #expect(item.detail?.hasPrefix("Overdue") == true)
        #expect(item.actions == [.done, .snooze, .open])
        // Overdue loans stay in Loans due; Overdue holds only other deadlines.
        #expect(!brief.sections.contains { $0.kind == .overdue })
    }

    @Test func FR_BOOK_04_clashShowsTheEarlierReturnTime() throws {
        let brief = compose(loans: [loan("b1", "Camera kit", due: at(16), location: "Desk", proposed: at(14, 45))])
        let item = try #require(brief.sections.first { $0.kind == .loans }?.items.first)
        #expect(item.detail?.contains("busy") == true)
        #expect(item.detail?.contains(BriefComposer.timeText(at(14, 45), calendar: dublin)) == true)
    }

    /// The time is formatted in the calendar's zone and locale, not the machine's.
    @Test func loanTimeUsesTheCalendarsZoneAndLocale() {
        var irish = dublin
        irish.locale = Locale(identifier: "en_IE")
        #expect(BriefComposer.timeText(at(14, 45), calendar: irish) == "14:45")
        var utc = irish
        utc.timeZone = TimeZone(identifier: "America/New_York")!
        #expect(BriefComposer.timeText(at(14, 45), calendar: utc) != "14:45")
    }

    /// The loan's return deadline is shown once, in Loans due, and only while it is open: done
    /// or snoozed deadlines are not passed in, so the loan drops out with them.
    @Test func loanDeadlineIsNotShownTwice() throws {
        let deadlines = [deadline("d-loan", "Camera kit", due: at(17)), deadline("d-other", "Hand in marks", due: at(12, day: 15))]
        let brief = compose(deadlines: deadlines, loans: [loan("b1", "Camera kit", due: at(17), deadline: "d-loan")])
        #expect(brief.sections.first { $0.kind == .loans }?.items.map(\.id) == ["loan.d-loan"])
        #expect(brief.sections.first { $0.kind == .deadlines }?.items.map(\.title) == ["Hand in marks"])

        let done = compose(deadlines: [deadlines[1]], loans: [loan("b1", "Camera kit", due: at(17), deadline: "d-loan")])
        #expect(!done.sections.contains { $0.kind == .loans })
    }

    @Test func loansComeAfterDeadlinesByDefault() {
        let brief = BriefComposer.compose(
            slot: morning, now: at(8), events: [], deadlines: [deadline("d", "Hand in marks", due: at(12, day: 15))],
            sources: BriefSources(nudges: [BriefNudge(id: "n", title: "Free", slot: DateInterval(start: at(18), duration: 3600), dataClass: .personal)],
                                  loans: [loan("b1", "Camera kit", due: at(17))]),
            calendar: dublin
        )
        #expect(brief.sections.map(\.kind) == [.deadlines, .loans, .keepInTouch])
    }

    /// BD-04: loan titles never reach the brief notification or the widget; they are counted.
    @Test func Boundary_B8_loanTitlesAreCountsOnlyOutsideTheApp() {
        let brief = compose(loans: [loan("b1", "Synthetic camera kit", due: at(17))])
        let content = BriefNotificationContent.make(for: brief)
        #expect(!content.body.contains("Synthetic") && !content.title.contains("Synthetic"))
        #expect(content.body.contains("college"))
        let widget = WidgetSnapshot.make(for: brief)
        #expect(widget.collegeCount == 1)
        #expect(widget.lines.isEmpty)
    }

    /// B-8 (brief half): with Claude allowed for personal items, loan lines are phrased only on
    /// device; no cloud request carries a loan title or location.
    @Test func Boundary_B8_cloudPhrasingExcludesLoans() async throws {
        let providers = RecordingProvider.oneOfEach()
        let router = AIRouter(
            providers: providers, ledger: InMemoryLedger(),
            policy: StaticPolicySource(PolicySnapshot(consents: [ConsentKey(sourceID: nil, purpose: .briefPhrase, tier: .anthropicCloud): UUID()])),
            catalog: try ModelCatalog.bundled()
        )
        let brief = BriefComposer.compose(
            slot: morning, now: at(8), events: [],
            deadlines: [BriefDeadline(id: "p", title: "Renew car tax", dueAt: at(17, day: 16), dataClass: .personal)],
            sources: BriefSources(loans: [loan("b1", "Synthetic camera kit", due: at(17), location: "Synthetic desk")]),
            calendar: dublin
        )
        _ = await BriefPhraser.phrase(brief, mode: .claudeForPersonal, router: router, calendar: dublin)
        let cloud = providers.filter { $0.locality.tier.leavesOwnerDevices }.flatMap(\.recordedCalls)
        #expect(!cloud.isEmpty) // the personal deadline did use Claude
        for call in cloud {
            let wire = String(decoding: call.wirePayload ?? Data(), as: UTF8.self)
            #expect(!wire.contains("Synthetic"))
            #expect(call.payloads.allSatisfy { $0.dataClass != .college })
        }
        let local = providers.filter { !$0.locality.tier.leavesOwnerDevices }.flatMap(\.recordedCalls)
        #expect(local.contains { call in call.payloads.contains { $0.text.contains("Synthetic camera kit") } })
    }

    /// An all-day deadline (a Canvas due date at 00:00) is due for the whole day: in Coming up
    /// on its day, overdue only from the next day.
    @Test func allDayDeadlineIsNotOverdueOnItsDay() throws {
        let essay = BriefDeadline(id: "c", title: "Essay draft", dueAt: dublin.startOfDay(for: at(8)), isAllDay: true, dataClass: .college)
        let today = compose(now: at(15), deadlines: [essay], loans: [])
        #expect(today.sections.map(\.kind) == [.deadlines])
        let tomorrow = compose(now: at(0, 30, day: 15), deadlines: [essay], loans: [])
        #expect(tomorrow.sections.map(\.kind) == [.overdue])
    }
}
