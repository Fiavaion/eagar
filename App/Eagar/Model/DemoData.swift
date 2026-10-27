import EagarBrief
import EagarCalendar
import EagarCore
import EagarMoney
import EagarPeople
import EagarStore
import Foundation

/// Synthetic trials, people and deadlines for screenshots and demos.
///
/// `-EagarDemoData YES` implies `-EagarInMemoryStores YES`, `-EagarFakeCalendar YES` (with
/// the rich demo week) and `-EagarSkipOnboarding YES`, then seeds these records at launch, so
/// Today, Deadlines, Subscriptions and People all have content. Every name, service and
/// address is made up; nothing touches real data or the network.
enum DemoData {
    static let launchArgument = "EagarDemoData"

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: launchArgument) }

    /// Seeds the stores once, relative to the model's clock, and confirms the demo calendars'
    /// proposed tags (Home personal, NCAD college).
    @MainActor
    static func seed(_ model: AppModel) async {
        let services = model.services
        let calendar = Calendar.current
        let now = model.money.now
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, hour: Int = 0) -> Date {
            let date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
            return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) ?? date
        }

        let trials = TrialRepository(stores: services.stores)
        let samples: [TrialSnapshot] = [
            TrialSnapshot(service: "Streamly", price: Decimal(string: "9.99")!, period: .monthly, isTrial: true, startedAt: day(-25), renewsAt: day(5)),
            TrialSnapshot(service: "Lingo Plus", price: Decimal(string: "59.99")!, period: .yearly, isTrial: true, startedAt: day(-1), renewsAt: day(8), cancelURL: URL(string: "https://example.com/lingo/cancel")),
            TrialSnapshot(service: "Cloudbox", price: Decimal(string: "2.99")!, period: .monthly, isTrial: false, startedAt: day(-200), renewsAt: day(14)),
            TrialSnapshot(service: "Sketchpad Pro", price: Decimal(string: "4.49")!, currencyCode: "GBP", period: .monthly, isTrial: false, startedAt: day(-90), renewsAt: day(21)),
            TrialSnapshot(service: "Newsly", price: Decimal(string: "6.00")!, period: .monthly, isTrial: true, renewsAt: day(-3), status: .cancelled, cancelledAt: day(-6)),
        ]
        do {
            for sample in samples { try await trials.upsert(sample, now: now, calendar: calendar) }
        } catch {
            EagarLog(.app).error("demo trials not seeded")
        }

        let people = PeopleRepository(stores: services.stores)
        let contacts = [
            ("demo.aoife", "Aoife Ní Bhriain", "aoife@example.ie", Birthday(month: calendar.component(.month, from: day(3)), day: calendar.component(.day, from: day(3)), year: 1990), 30, [Int]()),
            ("demo.cian", "Cian Ó Murchú", "cian@example.ie", Birthday(month: 3, day: 17), 14, [Int]()),
            ("demo.niamh", "Niamh Kelly", "niamh@example.ie", nil, 60, [7, 1]),
            ("demo.darragh", "Darragh Byrne", "darragh@example.ie", Birthday(month: 2, day: 29, year: 1988), 21, [5]),
            ("demo.ciara", "Ciara Walsh", "ciara@example.ie", nil, 28, [Int]()),
        ]
        do {
            for (identifier, name, email, birthday, cadence, weekdays) in contacts {
                let id = try await people.upsert(ContactImport(contactIdentifier: identifier, displayName: name, emailAddresses: [email], birthday: birthday), now: now)
                try await people.update(id) { person in
                    person.setCadence(days: cadence)
                    person.setPreferredWeekdays(weekdays)
                    // Ciara is a colleague: her college-calendar meetings count, on this device only.
                    person.workSignalsOptIn = identifier == "demo.ciara"
                    if identifier == "demo.niamh" { person.relationshipNotes = "Ask about the new studio." }
                }
                if identifier == "demo.darragh" {
                    try await people.log(ContactLogDraft(personID: id, occurredAt: day(-24, hour: 20)), now: now)
                }
            }
        } catch {
            EagarLog(.app).error("demo people not seeded")
        }

        do {
            try await services.stores.insert(Deadline(title: "Renew car tax", dueAt: day(2, hour: 17), dataClass: .personal, createdAt: now))
            try await services.stores.insert(Deadline(title: "Submit module descriptors", dueAt: day(3, hour: 12), dataClass: .college, createdAt: now))
        } catch {
            EagarLog(.app).error("demo deadlines not seeded")
        }

        await model.planner.loadCalendars()
        await model.planner.confirmProposedTags()
    }
}

/// Swallows every notification in demo mode, so synthetic records never reach the
/// notification centre.
struct DemoNotificationSink: NotificationScheduling, BriefNotificationScheduling, TrialReminderScheduling, BirthdayNotificationScheduling {
    func pendingIdentifiers() async -> [String] { [] }
    func add(_ planned: PlannedNotification) async throws {}
    func add(_ planned: PlannedTrialReminder) async throws {}
    func add(_ planned: PlannedBirthdayNotification) async throws {}
    func remove(identifiers: [String]) async {}
    func requestAuthorization() async throws -> Bool { false }
    func pendingBriefIdentifiers() async -> [String] { [] }
    func schedule(_ content: BriefNotificationContent, at date: Date, identifier: String) async throws {}
}
