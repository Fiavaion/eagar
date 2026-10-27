import AppIntents
import EagarCore
import EagarMoney
import EagarPeople
import Foundation

/// "Add a trial" for Shortcuts and Siri (FR-OS-03). Creates a personal trial through
/// `TrialDraft`, with the FR-TRIAL-01 defaults for anything not given, and schedules its
/// reminders.
struct AddTrialIntent: AppIntent {
    static let title: LocalizedStringResource = "Add a trial"
    static let description = IntentDescription("Adds a free trial or subscription to Eagar and reminds you before it bills.")

    @Parameter(title: "Service")
    var service: String

    @Parameter(title: "Price")
    var price: Double?

    @Parameter(title: "Renews on")
    var renewsAt: Date

    @Dependency private var services: AppServices

    init() {}

    init(service: String, price: Double?, renewsAt: Date) {
        self.service = service
        self.price = price
        self.renewsAt = renewsAt
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let draft = TrialDraft(service: service, price: price.map { Decimal($0) }, renewsAt: renewsAt)
        guard let snapshot = draft.confirmed() else { return .result(dialog: "The trial needs a service name.") }
        try await Self.add(snapshot, services: services, now: Date())
        return .result(dialog: "Added. Eagar will remind you before it bills.")
    }

    /// Stores the trial and reconciles every trial reminder. Shared with tests.
    static func add(_ snapshot: TrialSnapshot, services: AppServices, now: Date, calendar: Calendar = .current) async throws {
        let repository = TrialRepository(stores: services.stores)
        try await repository.upsert(snapshot, now: now, calendar: calendar)
        await TrialReminderSync.sync(trials: try await repository.all(), now: now, scheduler: services.trialReminders, calendar: calendar)
        await services.sync?.syncLocalChanges()
    }
}

/// A keep-in-touch person for Shortcuts. People are personal (BD-26); a record that reads as
/// college (an unknown class) is never offered (FR-OS-03: indexed entities exclude college).
struct PersonEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Person"
    static let defaultQuery = PersonEntityQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct PersonEntityQuery: EntityStringQuery {
    @Dependency private var services: AppServices

    init() {}

    func entities(for identifiers: [UUID]) async throws -> [PersonEntity] {
        try await Self.people(services).filter { identifiers.contains($0.id) }
    }

    func entities(matching string: String) async throws -> [PersonEntity] {
        try await Self.people(services).filter { $0.name.localizedStandardContains(string) }
    }

    func suggestedEntities() async throws -> [PersonEntity] {
        try await Self.people(services)
    }

    static func people(_ services: AppServices) async throws -> [PersonEntity] {
        try await PeopleRepository(stores: services.stores).people()
            .filter { $0.snapshot.dataClass != .college }
            .map { PersonEntity(id: $0.id, name: $0.snapshot.displayName) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

/// "Log contact" (FR-OS-03): records that Mark was in touch with someone today.
struct LogContactIntent: AppIntent {
    static let title: LocalizedStringResource = "Log contact"
    static let description = IntentDescription("Records that you were in touch with someone today.")

    @Parameter(title: "Person")
    var person: PersonEntity

    @Dependency private var services: AppServices

    init() {}

    init(person: PersonEntity) {
        self.person = person
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await Self.log(person.id, services: services, now: Date())
        return .result(dialog: "Logged.")
    }

    static func log(_ personID: UUID, services: AppServices, now: Date) async throws {
        try await PeopleRepository(stores: services.stores).log(ContactLogDraft(personID: personID, occurredAt: now), now: now)
        await services.sync?.syncLocalChanges()
    }
}
