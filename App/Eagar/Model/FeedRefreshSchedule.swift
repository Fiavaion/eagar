import EagarCore
import Foundation
#if os(iOS)
import BackgroundTasks
#endif

/// BGAppRefresh for the college feeds on iOS (FR-BOOK-02: devices refresh on open and in the
/// background). The identifier is listed in Info.plist `BGTaskSchedulerPermittedIdentifiers`.
/// macOS refreshes on activation only (the Mac hub polls from M3).
enum FeedRefreshSchedule {
    static let taskIdentifier = "app.eagar.feeds.refresh"
    /// The earliest the system may run the next refresh; it decides the actual time.
    static let interval: TimeInterval = 30 * 60

    static func submit() {
        #if os(iOS)
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: interval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // The simulator and Low Power Mode refuse; the next activation refreshes anyway.
            EagarLog(.feeds).notice("background feed refresh not scheduled")
        }
        #endif
    }
}
