import AppIntents
import SwiftUI
import WidgetKit

/// "Start brief" in Control Centre (FR-OS-02): opens Eagar on the Today tab. Shows no content.
struct StartBriefControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.eagar.startBrief") {
            ControlWidgetButton(action: StartBriefIntent()) {
                Label("Start brief", systemImage: "sun.horizon")
            }
        }
        .displayName("Start brief")
        .description("Opens Eagar on today's brief.")
    }
}
