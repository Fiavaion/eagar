import AppIntents
import EagarCore
import SwiftUI
import WidgetKit

/// The global kill switch in Control Centre (FR-CORE-07, FR-OS-02, BD-11). It flips the shared
/// state; the app halts all AI as soon as it sees the change.
struct KillSwitchControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.eagar.killSwitch", provider: KillSwitchValueProvider()) { engaged in
            ControlWidgetToggle("Stop Eagar AI", isOn: engaged, action: SetKillSwitchIntent()) { isOn in
                Label(isOn ? "AI stopped" : "AI on", systemImage: isOn ? "stop.circle.fill" : "stop.circle")
            }
        }
        .displayName("Stop Eagar AI")
        .description("Stops all drafting and AI at once.")
    }
}

struct KillSwitchValueProvider: ControlValueProvider {
    var previewValue: Bool { false }
    func currentValue() async throws -> Bool { EagarAppGroup.killSwitch.isEngaged }
}
