import Foundation

/// The App Group shared by the app and its extensions (D-016).
public enum EagarAppGroup {
    public static let identifier = "group.com.fiavaion.eagarapp"

    /// The group container, or `nil` when the build has no App Group entitlement (unsigned/CI).
    public static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// The kill switch state shared with the Control Centre control.
    public static var killSwitch: KillSwitchState {
        KillSwitchState(suiteName: containerURL == nil ? nil : identifier)
    }

    /// Where the app writes the widget snapshot.
    public static var widgetSnapshotURL: URL? {
        containerURL?.appending(path: "brief-widget.json")
    }
}

/// What widgets show (FR-BRIEF-06, FR-OS-01). Built by the app from the brief; read by the
/// widget extension. College items never contribute a title: they appear only in `collegeCount`.
public struct WidgetSnapshot: Sendable, Hashable, Codable {
    public struct Line: Sendable, Hashable, Codable {
        public let title: String
        public let start: Date?

        public init(title: String, start: Date?) {
            self.title = title
            self.start = start
        }
    }

    public let generatedAt: Date
    public let lines: [Line]
    public let collegeCount: Int
    public let nextDeadline: Date?

    public init(generatedAt: Date, lines: [Line], collegeCount: Int, nextDeadline: Date?) {
        self.generatedAt = generatedAt
        self.lines = lines
        self.collegeCount = collegeCount
        self.nextDeadline = nextDeadline
    }

    public static let placeholder = WidgetSnapshot(generatedAt: .distantPast, lines: [], collegeCount: 0, nextDeadline: nil)

    /// Reads the snapshot the app last wrote; `nil` if there is none.
    public static func load(from url: URL? = EagarAppGroup.widgetSnapshotURL) -> WidgetSnapshot? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }

    /// Writes the snapshot atomically.
    public func save(to url: URL? = EagarAppGroup.widgetSnapshotURL) throws {
        guard let url else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
