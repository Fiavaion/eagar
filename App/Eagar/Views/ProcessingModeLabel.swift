import EagarCore
import SwiftUI

/// Where a calendar's data may be processed (FR-CORE-06, BD-04). Shape and text, never colour
/// alone: a house for college ("stays on your devices"), a cloud for personal.
struct ProcessingModeLabel: View {
    let dataClass: DataClass
    /// `true` shows only the class name next to the icon (picker rows).
    var compact = false

    private var isCollege: Bool { dataClass == .college }

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 0) {
                Text(DataClassLabel.name(dataClass))
                if !compact {
                    Text(isCollege ? "Stays on your devices · Local AI only" : "Cloud AI with your consent")
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: isCollege ? "house.fill" : "cloud")
        }
        .font(.caption)
        .labelStyle(.titleAndIcon)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            isCollege
                ? Text("College. Stays on your devices, local AI only.")
                : Text("Personal. Cloud AI with your consent.")
        )
        .accessibilityIdentifier(isCollege ? "processing.college" : "processing.personal")
    }
}
