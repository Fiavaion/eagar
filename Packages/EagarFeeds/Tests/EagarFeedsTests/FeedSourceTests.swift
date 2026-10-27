import EagarCore
import Testing
@testable import EagarFeeds

/// FR-CORE-04: default class and processing mode for new feed sources.
struct FeedSourceTests {
    struct Case: Sendable, CustomTestStringConvertible {
        let kind: FeedKind
        let host: String?
        let profile: ProfileKind
        let dataClass: DataClass
        let mode: ProcessingMode
        var testDescription: String { "\(kind.rawValue) \(host ?? "nil") \(profile.rawValue)" }
    }

    static let cases: [Case] = [
        Case(kind: .iCalendar, host: "ncad.ie", profile: .owner, dataClass: .college, mode: .localAI),
        Case(kind: .iCalendar, host: "timetable.ncad.ie", profile: .owner, dataClass: .college, mode: .localAI),
        Case(kind: .iCalendar, host: "NCAD.IE", profile: .owner, dataClass: .college, mode: .localAI),
        Case(kind: .iCalendar, host: "cdbooking.com", profile: .owner, dataClass: .college, mode: .localAI),
        Case(kind: .iCalendar, host: "ncad.instructure.com", profile: .owner, dataClass: .college, mode: .localAI),
        Case(kind: .iCalendar, host: "ncad.ie", profile: .other, dataClass: .college, mode: .rulesOnly),
        Case(kind: .iCalendar, host: "cdbooking.com", profile: .other, dataClass: .college, mode: .rulesOnly),
        Case(kind: .iCalendar, host: "notncad.ie", profile: .owner, dataClass: .personal, mode: .cloudAllowed),
        Case(kind: .iCalendar, host: "ncad.ie.example.com", profile: .owner, dataClass: .personal, mode: .cloudAllowed),
        Case(kind: .iCalendar, host: "calendar.example.com", profile: .other, dataClass: .personal, mode: .rulesOnly),
        Case(kind: .iCalendar, host: nil, profile: .owner, dataClass: .personal, mode: .cloudAllowed),
        // cdbooking and Canvas are college by kind, whatever the host (BD-15, FR-CANVAS-02).
        Case(kind: .cdbooking, host: "bookings.example.org", profile: .owner, dataClass: .college, mode: .localAI),
        Case(kind: .canvas, host: "someother.instructure.com", profile: .owner, dataClass: .college, mode: .localAI),
        Case(kind: .canvas, host: nil, profile: .other, dataClass: .college, mode: .rulesOnly),
    ]

    @Test(arguments: cases)
    func defaults(_ c: Case) {
        let defaults = FeedSourceDefaults.proposed(kind: c.kind, host: c.host, profile: c.profile)
        #expect(defaults.dataClass == c.dataClass)
        #expect(defaults.processingMode == c.mode)
        #expect(defaults.boundary == (c.dataClass == .college ? .localOnly : .cloudAllowed))
    }

    @Test func collegeKindsCannotBeConfiguredAsPersonal() {
        #expect(FeedSource(kind: .cdbooking, dataClass: .personal, processingMode: .cloudAllowed).dataClass == .college)
        #expect(FeedSource(kind: .canvas, dataClass: .publicContent, processingMode: .cloudAllowed).dataClass == .college)
        #expect(FeedSource(kind: .iCalendar, dataClass: .personal, processingMode: .cloudAllowed).dataClass == .personal)
    }

    /// BD-04: a college source can never carry `cloudAllowed`; it is clamped to local AI.
    @Test func Boundary_collegeSourcesCannotBeCloudAllowed() {
        #expect(FeedSource(kind: .cdbooking, dataClass: .personal, processingMode: .cloudAllowed).processingMode == .localAI)
        #expect(FeedSource(kind: .canvas, dataClass: .college, processingMode: .cloudAllowed).processingMode == .localAI)
        #expect(FeedSource(kind: .iCalendar, dataClass: .college, processingMode: .cloudAllowed).processingMode == .localAI)
        #expect(FeedSource(kind: .canvas, dataClass: .college, processingMode: .rulesOnly).processingMode == .rulesOnly)
        #expect(FeedSource(kind: .iCalendar, dataClass: .personal, processingMode: .cloudAllowed).processingMode == .cloudAllowed)
        // A record stored with a cloud mode reads back clamped.
        let record = FeedSourceRecord(source: FeedSource(kind: .canvas, dataClass: .college, processingMode: .localAI), displayName: "C", createdAt: .distantPast)
        record.processingModeRaw = ProcessingMode.cloudAllowed.rawValue
        #expect(record.state.source.processingMode == .localAI)
    }

    @Test func extraDomainsCanBeSupplied() {
        let defaults = FeedSourceDefaults.proposed(kind: .iCalendar, host: "canvas.example.edu", profile: .owner, collegeDomains: ["example.edu"])
        #expect(defaults.dataClass == .college)
    }
}
