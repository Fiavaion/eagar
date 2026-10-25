import AppIntents
import EagarCore

/// Sets the global kill switch (FR-CORE-07). Compiled into both the app and the widget
/// extension: the Control Centre control runs it in the extension, Shortcuts in the app.
/// The app halts all AI as soon as it sees the state change.
struct SetKillSwitchIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Stop Eagar AI"
    static let description = IntentDescription("Stops all drafting and AI in Eagar at once, or allows it again.")

    @Parameter(title: "Stopped")
    var value: Bool

    init() {}

    init(value: Bool) {
        self.value = value
    }

    func perform() async throws -> some IntentResult {
        EagarAppGroup.killSwitch.set(engaged: value)
        return .result()
    }
}
