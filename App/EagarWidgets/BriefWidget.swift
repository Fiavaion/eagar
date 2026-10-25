import EagarCore
import SwiftUI
import WidgetKit

/// The brief at a glance (FR-BRIEF-06, FR-OS-01). Personal items by title; college items only
/// as a count, with the house symbol meaning "stays on your devices".
struct BriefWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "app.eagar.brief", provider: SnapshotProvider()) { entry in
            BriefWidgetView(snapshot: entry.snapshot)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Brief")
        .description("Your next items, with college items shown as a count.")
        .supportedFamilies(Self.families)
    }

    /// Lock Screen families exist on iOS only.
    static var families: [WidgetFamily] {
        #if os(iOS)
        [.systemSmall, .systemMedium, .accessoryRectangular]
        #else
        [.systemSmall, .systemMedium]
        #endif
    }
}

struct BriefWidgetView: View {
    let snapshot: WidgetSnapshot
    @Environment(\.widgetFamily) private var family

    private var maxLines: Int { family == .systemMedium ? 4 : 2 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if snapshot.lines.isEmpty && snapshot.collegeCount == 0 {
                Text("Nothing needs you right now.")
                    .font(.caption)
            }
            ForEach(Array(snapshot.lines.prefix(maxLines).enumerated()), id: \.offset) { _, line in
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let start = line.start {
                        Text(start, style: .time).font(.caption2).foregroundStyle(.secondary)
                    }
                    Text(line.title).font(.caption).lineLimit(1)
                }
            }
            if snapshot.collegeCount > 0 {
                Label {
                    Text("College items: \(snapshot.collegeCount)")
                } icon: {
                    Image(systemName: "house")
                }
                .font(.caption)
                .accessibilityLabel(Text("College items: \(snapshot.collegeCount). They stay on your devices."))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
