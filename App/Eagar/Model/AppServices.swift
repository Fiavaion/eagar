import EagarAI
import EagarCalendar
import EagarCore
import EagarLedger
import EagarMoney
import EagarPeople
import EagarSecurity
import EagarStore
import EagarSync
import EagarSuggest
import Foundation
import SwiftData
import Synchronization

/// The long-lived services, built once at launch.
struct AppServices: Sendable {
    let stores: EagarStores
    let ledger: PrivacyLedger
    let consents: ConsentRegistry
    let router: AIRouter
    let secrets: any SecretStore
    let catalog: ModelCatalog
    let policy: AppPolicySource
    /// EventKit, or the synthetic ``DemoEventStore`` under `-EagarFakeCalendar YES`.
    let eventStore: any EventStoreAdapting
    let calendarTags: CalendarTagStore
    let eventLog: EventLog
    let deadlineNotifications: any NotificationScheduling
    let briefNotifications: any BriefNotificationScheduling
    /// PersonalStore sync (BD-02). `nil` unless the build has the iCloud entitlement (D-020).
    let sync: PersonalSyncEngine?
    let donations: any IntentDonating
    let widgets: any WidgetPublishing
    /// Trial reminders at 7/3/1/0 days before cancel-by (FR-TRIAL-02).
    let trialReminders: any TrialReminderScheduling
    /// Birthday reminders (FR-PEOPLE-06).
    let birthdayNotifications: any BirthdayNotificationScheduling
    /// Trials proposed by the share extension, waiting for confirmation (FR-TRIAL-03).
    let pendingImports: PendingTrialImportStore

    /// Every SwiftData model in the app. Both stores share one schema; placement is per record.
    static var models: [any PersistentModel.Type] {
        [
            LedgerEntry.self, ConsentRecord.self, CalendarRef.self, Deadline.self, EventLogEntry.self,
            Trial.self, Person.self, ContactLog.self,
        ]
    }

    static func make(
        inMemory: Bool,
        secrets: any SecretStore = Keychain(),
        eventStore: any EventStoreAdapting = EventKitAdapter(),
        deadlineNotifications: any NotificationScheduling = UserNotificationScheduler(),
        briefNotifications: any BriefNotificationScheduling = UserBriefNotificationScheduler(),
        donations: any IntentDonating = SystemIntentDonor(),
        widgets: any WidgetPublishing = SystemWidgetPublisher(),
        trialReminders: any TrialReminderScheduling = UserTrialReminderScheduler(),
        birthdayNotifications: any BirthdayNotificationScheduling = UserBirthdayNotificationScheduler(),
        pendingImports: PendingTrialImportStore = .appGroup
    ) throws -> AppServices {
        let location: StoreLocation = inMemory
            ? .inMemory
            : .directory(URL.applicationSupportDirectory.appending(path: "Eagar", directoryHint: .isDirectory))
        let stores = try EagarStores(location: location, models: models)
        let ledger = PrivacyLedger(stores: stores, authenticator: DeviceOwnerAuthenticator())
        let consents = ConsentRegistry(stores: stores)
        let catalog = try ModelCatalog.bundled()
        let policy = AppPolicySource(consents: consents, ledger: ledger)
        let router = AIRouter(
            providers: [AppleOnDeviceProvider(), AnthropicProvider(secrets: secrets)],
            ledger: ledger,
            policy: policy,
            catalog: catalog
        )
        return AppServices(
            stores: stores, ledger: ledger, consents: consents, router: router,
            secrets: secrets, catalog: catalog, policy: policy,
            eventStore: eventStore, calendarTags: CalendarTagStore(stores: stores), eventLog: EventLog(stores: stores),
            deadlineNotifications: deadlineNotifications, briefNotifications: briefNotifications,
            sync: inMemory ? nil : makeSync(stores: stores), donations: donations, widgets: widgets,
            trialReminders: trialReminders, birthdayNotifications: birthdayNotifications, pendingImports: pendingImports
        )
    }

    static let iCloudContainer = "iCloud.com.fiavaion.eagarapp"

    /// Sync is compiled in only for team-signed builds (`EAGAR_CLOUDKIT`, set in Local.xcconfig):
    /// creating a CloudKit container without the iCloud entitlement crashes, and CI builds are
    /// unsigned. Only PersonalStore is synced; the coordinator refuses CollegeStore.
    static func makeSync(stores: EagarStores) -> PersonalSyncEngine? {
        #if EAGAR_CLOUDKIT
        let stateURL = URL.applicationSupportDirectory.appending(path: "Eagar/Sync/personal-sync.json")
        do {
            let adapters = [
                AnySyncAdapter(DeadlineSyncAdapter()), AnySyncAdapter(TrialSyncAdapter()),
                AnySyncAdapter(PersonSyncAdapter()), AnySyncAdapter(ContactLogSyncAdapter()),
            ]
            let coordinator = try SyncCoordinator(store: stores.personal, adapters: adapters, stateURL: stateURL)
            return PersonalSyncEngine(containerIdentifier: iCloudContainer, coordinator: coordinator)
        } catch {
            EagarLog(.app).error("personal sync not started")
            return nil
        }
        #else
        return nil
        #endif
    }
}

/// Builds the router's policy for each request from consents and the spend cap. M0 has no
/// data sources yet, so no source modes are registered (unknown sources fail closed).
final class AppPolicySource: PolicySource {
    private let consents: ConsentRegistry
    private let ledger: PrivacyLedger
    private let cap = Mutex<Int64?>(nil)

    init(consents: ConsentRegistry, ledger: PrivacyLedger) {
        self.consents = consents
        self.ledger = ledger
    }

    func setMonthlyCap(microUSD: Int64?) {
        cap.withLock { $0 = microUSD }
    }

    var monthlyCapMicroUSD: Int64? { cap.withLock { $0 } }

    func snapshot() async throws -> PolicySnapshot {
        let meter = SpendMeter(monthlyCapMicroUSD: monthlyCapMicroUSD)
        let paused = meter.isCapReached(try await ledger.records(), now: Date())
        return PolicySnapshot(consents: try await consents.active(), cloudPaused: paused)
    }
}
