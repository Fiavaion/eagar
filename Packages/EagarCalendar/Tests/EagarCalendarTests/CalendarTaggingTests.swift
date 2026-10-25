import EagarCore
import EagarStore
import Foundation
import SwiftData
import Testing
@testable import EagarCalendar
import EagarCalendarTestSupport

private let ncad = CalendarInfo(id: "ncad-cal", title: "Work", accountTitle: "m.jones@ncad.ie", sourceKind: .calDAV, entity: .event, allowsModification: true)
private let staffSub = CalendarInfo(id: "ncad-sub", title: "Staff", accountTitle: "someone@staff.ncad.ie", sourceKind: .calDAV, entity: .event, allowsModification: true)
private let home = CalendarInfo(id: "home-cal", title: "Home", accountTitle: "iCloud", sourceKind: .iCloud, entity: .event, allowsModification: true)
private let lookalike = CalendarInfo(id: "fake", title: "X", accountTitle: "mark@notncad.ie", sourceKind: .calDAV, entity: .event, allowsModification: true)

private func makeStore() throws -> CalendarTagStore {
    CalendarTagStore(stores: try EagarStores(location: .inMemory, models: [CalendarRef.self]))
}

struct CalendarTaggingTests {
    @Test func collegeDomainMatching() {
        #expect(CollegeDomains.matches("m.jones@ncad.ie"))
        #expect(CollegeDomains.matches("M.Jones@NCAD.IE"))
        #expect(CollegeDomains.matches("someone@staff.ncad.ie"))
        #expect(!CollegeDomains.matches("mark@notncad.ie"))
        #expect(!CollegeDomains.matches("iCloud"))
        #expect(!CollegeDomains.matches(""))
    }

    /// FR-CAL-02 / M1 acceptance: an ncad.ie account's calendars are pre-tagged college.
    @Test func ncadCalendarsArePreTaggedCollege() async throws {
        let tags = try await makeStore().tags(for: [ncad, staffSub, home, lookalike])
        #expect(tags["ncad-cal"]?.dataClass == .college)
        #expect(tags["ncad-sub"]?.dataClass == .college)
        #expect(tags["home-cal"]?.dataClass == .personal)
        #expect(tags["fake"]?.dataClass == .personal)
        #expect(tags.values.allSatisfy { !$0.confirmed })
    }

    @Test func markCanRetagAndRefsMoveStores() async throws {
        let stores = try EagarStores(location: .inMemory, models: [CalendarRef.self])
        let tagStore = CalendarTagStore(stores: stores)
        try await tagStore.setTag(home, dataClass: .college, includeInBrief: false)
        var tags = try await tagStore.tags(for: [home])
        #expect(tags["home-cal"] == CalendarTag(calendarID: "home-cal", dataClass: .college, includeInBrief: false, confirmed: true))
        #expect(try await stores.college.fetch(FetchDescriptor<CalendarRef>()) { $0.calendarIdentifier } == ["home-cal"])

        try await tagStore.setTag(home, dataClass: .personal)
        tags = try await tagStore.tags(for: [home])
        #expect(tags["home-cal"]?.dataClass == .personal)
        #expect(try await stores.college.fetch(FetchDescriptor<CalendarRef>()) { $0.calendarIdentifier }.isEmpty)
        #expect(try await stores.personal.fetch(FetchDescriptor<CalendarRef>()) { $0.calendarIdentifier } == ["home-cal"])
    }

    /// Review finding (D-017): only a confirmed personal tag makes an event personal; unknown
    /// calendars and unconfirmed proposals are college.
    @Test func Boundary_classifierFailsClosedUntilConfirmed() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let events = [
            CalendarEvent(id: "1", calendarID: "home-cal", title: "Dentist", start: start, end: start + 1800),
            CalendarEvent(id: "2", calendarID: "never-seen", title: "?", start: start, end: start + 1800),
            CalendarEvent(id: "3", calendarID: "subscribed-canvas", title: "Assignment due", start: start, end: start + 1800),
        ]
        let tags = [
            "home-cal": CalendarTag(calendarID: "home-cal", dataClass: .personal, includeInBrief: true, confirmed: true),
            "subscribed-canvas": CalendarTag(calendarID: "subscribed-canvas", dataClass: .personal, includeInBrief: true, confirmed: false),
        ]
        let classified = CalendarClassifier.classify(events, tags: tags)
        #expect(classified.map(\.dataClass) == [.personal, .college, .college])
    }

    @Test func calendarTitlesNamingTheCollegeAreProposedCollege() async throws {
        let feed = CalendarInfo(id: "feed", title: "NCAD.ie timetable", accountTitle: "Subscribed Calendars", sourceKind: .subscribed, entity: .event, allowsModification: false)
        #expect(try makeStore().proposedClass(for: feed) == .college)
    }

    /// FR-CAL-04: college-derived content is never written into a personal calendar.
    @Test func Boundary_crossBoundaryWriteIsRefused() async throws {
        let fake = FakeEventStore(calendars: [ncad, home])
        let writer = CalendarWriter(store: fake)
        let draft = EventDraft(title: "Kit return", start: Date(), end: Date() + 600)
        let personalTag = CalendarTag(calendarID: "home-cal", dataClass: .personal, includeInBrief: true, confirmed: true)
        let collegeTag = CalendarTag(calendarID: "ncad-cal", dataClass: .college, includeInBrief: true, confirmed: true)

        await #expect(throws: CalendarError.crossBoundaryWrite) {
            try await writer.save(draft, derivedFrom: [.personal, .college], to: home, tag: personalTag)
        }
        #expect(fake.state.withLock { $0.savedEvents.isEmpty })

        _ = try await writer.save(draft, derivedFrom: [.college], to: ncad, tag: collegeTag)
        _ = try await writer.save(draft, derivedFrom: [.personal], to: home, tag: personalTag)
        _ = try await writer.save(draft, derivedFrom: [.personal], to: ncad, tag: collegeTag) // personal into college is allowed
        #expect(fake.state.withLock { $0.savedEvents.map(\.calendarID) } == ["ncad-cal", "home-cal", "ncad-cal"])
    }

    /// FR-CAL-06.
    @Test func missingNcadCalendarDiagnosis() {
        #expect(CalendarDiagnosis.isCollegeCalendarMissing([home, lookalike]))
        #expect(!CalendarDiagnosis.isCollegeCalendarMissing([home, ncad]))
        let ncadReminders = CalendarInfo(id: "r", title: "R", accountTitle: "m@ncad.ie", sourceKind: .calDAV, entity: .reminder, allowsModification: true)
        #expect(CalendarDiagnosis.isCollegeCalendarMissing([ncadReminders]))
    }

    @Test func eventKitSourceMapping() {
        // Mapping of EKSource types is covered through EventKitAdapter.sourceKind on a real store in
        // the app's hosted tests; here we cover the pure title rule.
        #expect(CollegeDomains.matches("x@ncad.ie", domains: ["ncad.ie", "cdbooking.com"]))
        #expect(CollegeDomains.matches("x@cdbooking.com", domains: ["ncad.ie", "cdbooking.com"]))
    }
}
