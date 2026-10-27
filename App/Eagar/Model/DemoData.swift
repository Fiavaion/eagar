import EagarBrief
import EagarCalendar
import EagarCore
import EagarFeeds
import EagarMoney
import EagarPeople
import EagarSecurity
import EagarStore
import Foundation
import Synchronization

/// Synthetic trials, people, deadlines, loans and Canvas items for screenshots and demos.
///
/// `-EagarDemoData YES` implies `-EagarInMemoryStores YES`, `-EagarFakeCalendar YES` (with
/// the rich demo week) and `-EagarSkipOnboarding YES`, then seeds these records at launch, so
/// Today, Deadlines, Subscriptions and People all have content. Loans and Canvas items come
/// through the real feed pipeline from ``DemoFeedTransport``. Every name, service and address
/// is made up; nothing touches real data, the Keychain or the network.
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

        // The cdbooking calendar feed (no API token, so the iCal path) and the Canvas feed.
        await model.feeds.connectBooking(feedURL: DemoFeedTransport.cdbookingFeedURL, apiToken: "", requestNotifications: false)
        await model.feeds.connectCanvas(feedURL: DemoFeedTransport.canvasFeedURL, requestNotifications: false)
    }
}

/// Serves synthetic cdbooking and Canvas iCalendar feeds, built relative to the current time:
/// one loan due today (the Live Activity), one due tomorrow at noon during the demo
/// calendar's portfolio reviews (a return clash), an all-day and a timed Canvas assignment and
/// a Canvas event. Hosts are under `.invalid`, so nothing could resolve even by mistake.
struct DemoFeedTransport: HTTPTransport {
    static let cdbookingFeedURL = "webcal://cdbooking.example.invalid/ical/demo-feed.ics"
    static let canvasFeedURL = "https://canvas.example.invalid/feeds/calendars/user_demo.ics"

    func send(_ request: URLRequest) async throws(FeedFetchError) -> HTTPResponse {
        let url = request.url
        switch (url?.host(), url?.path().contains("/ical/")) {
        case ("cdbooking.example.invalid", true?): return HTTPResponse(status: 200, body: Data(Self.cdbookingFeed(now: Date()).utf8))
        case ("canvas.example.invalid", _): return HTTPResponse(status: 200, body: Data(Self.canvasFeed(now: Date()).utf8))
        default: return HTTPResponse(status: 404)
        }
    }

    /// `20261027T101500Z`.
    private static func utc(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(dateSeparator: .omitted, timeSeparator: .omitted))
    }

    private static func day(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    static func cdbookingFeed(now: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let endOfToday = calendar.date(byAdding: .day, value: 1, to: today)?.addingTimeInterval(-60) ?? now
        let fivePM = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: today) ?? now
        let dueToday = now < fivePM.addingTimeInterval(-3600) ? fivePM : min(now.addingTimeInterval(45 * 60), endOfToday)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let dueTomorrow = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        let out = calendar.date(byAdding: .day, value: -2, to: today) ?? today
        return """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Eagar demo//cdbooking//EN
        BEGIN:VEVENT
        UID:booking-demo-1@cdbooking.example.invalid
        SUMMARY:Camera kit (demo)
        LOCATION:Media loans desk
        DTSTART:\(utc(out))
        DUE:\(utc(dueToday))
        X-CDB-STATUS:checked_out
        X-CDB-KIND:equipment
        URL:https://cdbooking.example.invalid/bookings/demo-1
        END:VEVENT
        BEGIN:VEVENT
        UID:booking-demo-2@cdbooking.example.invalid
        SUMMARY:Tripod and lights (demo)
        LOCATION:Media loans desk
        DTSTART:\(utc(out))
        DUE:\(utc(dueTomorrow))
        X-CDB-STATUS:checked_out
        X-CDB-KIND:equipment
        URL:https://cdbooking.example.invalid/bookings/demo-2
        END:VEVENT
        END:VCALENDAR

        """
    }

    static func canvasFeed(now: Date, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let inThree = calendar.date(byAdding: .day, value: 3, to: today) ?? today
        let inFive = calendar.date(byAdding: .day, value: 5, to: today) ?? today
        let timedDue = calendar.date(bySettingHour: 17, minute: 0, second: 0, of: inFive) ?? inFive
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let briefing = calendar.date(bySettingHour: 14, minute: 0, second: 0, of: tomorrow) ?? tomorrow
        return """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Eagar demo//Canvas//EN
        X-WR-CALNAME:Demo Canvas
        BEGIN:VEVENT
        UID:event-assignment-1001
        SUMMARY:Visual culture essay draft [VC201]
        DTSTART;VALUE=DATE:\(day(inThree, calendar: calendar))
        URL:https://canvas.example.invalid/courses/501/assignments/1001
        END:VEVENT
        BEGIN:VEVENT
        UID:event-assignment-1002
        SUMMARY:Studio portfolio upload [STU301]
        DTSTART:\(utc(timedDue))
        DTEND:\(utc(timedDue))
        URL:https://canvas.example.invalid/courses/502/assignments/1002
        END:VEVENT
        BEGIN:VEVENT
        UID:event-calendar-event-2001
        SUMMARY:Reading week briefing [STU301]
        DTSTART:\(utc(briefing))
        DTEND:\(utc(briefing.addingTimeInterval(3600)))
        URL:https://canvas.example.invalid/calendar?event_id=2001&include_contexts=course_502
        END:VEVENT
        END:VCALENDAR

        """
    }
}

/// Secrets for demo mode only: kept in memory, so demo feed addresses never reach the Keychain.
final class EphemeralSecretStore: SecretStore {
    private let values = Mutex<[String: String]>([:])

    func set(_ secret: Secret, for key: SecretKey) throws(SecurityError) { values.withLock { $0[key.account] = secret.reveal() } }
    func get(_ key: SecretKey) throws(SecurityError) -> Secret? { values.withLock { $0[key.account] }.map(Secret.init) }
    func delete(_ key: SecretKey) throws(SecurityError) { _ = values.withLock { $0.removeValue(forKey: key.account) } }
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
