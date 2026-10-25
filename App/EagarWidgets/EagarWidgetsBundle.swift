import SwiftUI
import WidgetKit

@main
struct EagarWidgetsBundle: WidgetBundle {
    var body: some Widget {
        BriefWidget()
        NextDeadlineWidget()
        KillSwitchControl()
        StartBriefControl()
    }
}
