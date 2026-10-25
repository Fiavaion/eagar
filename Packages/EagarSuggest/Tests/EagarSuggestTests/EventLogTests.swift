import EagarCore
import EagarStore
import Foundation
import SwiftData
import Testing
@testable import EagarSuggest

struct StepClock: EagarClock {
    let base = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { base }
}

struct EventLogTests {
    @Test func recordsArePlacedByClassAndReadBack() async throws {
        let stores = try EagarStores(location: .inMemory, models: [EventLogEntry.self])
        let log = EventLog(stores: stores, clock: StepClock())
        try await log.record(.briefOpened, subject: "brief-1", dataClass: .personal)
        try await log.record(.itemDone, subject: "deadline-7", dataClass: .college)
        try await log.record(.briefCompleted, subject: "brief-1", value: 95, dataClass: .personal)

        let records = try await log.records()
        #expect(Set(records.map(\.kind)) == [.briefOpened, .itemDone, .briefCompleted])
        #expect(records.first { $0.kind == .briefCompleted }?.value == 95)
        let college: [String] = try await stores.college.fetch(FetchDescriptor<EventLogEntry>()) { $0.subjectRef }
        let personal: [String] = try await stores.personal.fetch(FetchDescriptor<EventLogEntry>()) { $0.subjectRef }
        #expect(college == ["deadline-7"])
        #expect(personal.count == 2)
    }

    @Test func kindsAreContentFree() {
        #expect(EventLogKind.allCases.allSatisfy { !$0.logDescription.isEmpty })
    }
}
