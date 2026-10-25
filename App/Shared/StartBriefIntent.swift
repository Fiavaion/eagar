import AppIntents
import Foundation

extension Notification.Name {
    /// Posted in the app process when something asks to show today's brief (the Control Centre
    /// control, a brief notification). The root view switches to the Today tab.
    static let eagarShowBrief = Notification.Name("app.eagar.showBrief")
}

/// Opens Eagar on the Today tab (FR-OS-02). Compiled into both the app and the widget
/// extension: the Control Centre button names it in the extension, and the system runs it in
/// the app, which it opens first.
struct StartBriefIntent: AppIntent {
    static let title: LocalizedStringResource = "Start brief"
    static let description = IntentDescription("Opens Eagar on today's brief.")
    static let openAppWhenRun = true

    init() {}

    @MainActor
    func perform() async throws -> some IntentResult {
        NotificationCenter.default.post(name: .eagarShowBrief, object: nil)
        return .result()
    }
}
