import EagarCore
import SwiftUI
import WidgetKit

/// Time until the next deadline (FR-OS-01). Shows only a time, never a title, so it is safe on
/// the Lock Screen whatever the deadline's class.
struct NextDeadlineWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.eagar.nextDeadline", provider: SnapshotProvider()) { entry in
            NextDeadlineView(next: entry.snapshot.nextDeadline)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Next deadline")
        .description("How long until your next deadline.")
        .supportedFamilies(Self.families)
    }

    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .accessoryCircular, .accessoryInline]
        #else
        [.systemSmall]
        #endif
    }
}

struct NextDeadlineView: View {
    let next: Date?

    var body: some View {
        if let next {
            VStack {
                Image(systemName: "flag")
                Text(next, style: .relative).font(.caption).multilineTextAlignment(.center)
            }
            .accessibilityElement(children: .combine)
        } else {
            Text("No deadlines").font(.caption)
        }
    }
}
