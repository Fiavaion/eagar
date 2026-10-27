import EagarBrief
import EagarCore
import Foundation

/// Mark's brief settings (FR-BRIEF-01, FR-BRIEF-04, FR-BRIEF-07), kept in UserDefaults.
struct BriefSettings: Codable, Equatable {
    struct SlotSetting: Codable, Equatable, Identifiable {
        var kind: BriefSlot.Kind
        var enabled: Bool
        var hour: Int
        var minute: Int
        var id: BriefSlot.Kind { kind }

        var slot: BriefSlot { BriefSlot(kind: kind, hour: hour, minute: minute) }
    }

    /// Morning on at 08:00; midday and end of day off until Mark turns them on.
    var slots: [SlotSetting] = [
        SlotSetting(kind: .morning, enabled: true, hour: 8, minute: 0),
        SlotSetting(kind: .midday, enabled: false, hour: 12, minute: 30),
        SlotSetting(kind: .endOfDay, enabled: false, hour: 17, minute: 30),
    ]
    var preferences: BriefPreferences = .default
    /// Off by default: models can invent details, so Mark opts in (D-019).
    var phrasingMode: BriefPhrasingMode = .off

    static let defaultsKey = "brief.settings"

    var enabledSlots: [BriefSlot] {
        slots.filter(\.enabled).map(\.slot).sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    /// The sections filled so far (M1, M2), in Mark's order. Overdue is always shown first (FR-DL-04).
    static let steerableSections: [BriefSectionKind] = [.today, .deadlines, .loans, .trials, .keepInTouch]

    var orderedSteerableSections: [BriefSectionKind] {
        let ordered = preferences.order.filter(Self.steerableSections.contains)
        return ordered + Self.steerableSections.filter { !ordered.contains($0) }
    }

    /// Swaps a steerable section with its neighbour (button equivalent of drag to reorder).
    mutating func move(_ kind: BriefSectionKind, by offset: Int) {
        var visible = orderedSteerableSections
        guard let index = visible.firstIndex(of: kind), visible.indices.contains(index + offset) else { return }
        visible.swapAt(index, index + offset)
        preferences.order = [.overdue] + visible + BriefSectionKind.allCases.filter { $0 != .overdue && !visible.contains($0) }
    }

    /// Where unreadable settings are kept, so the next save does not destroy them.
    static let backupKey = "brief.settings.unreadable"

    /// Unreadable settings are moved to ``backupKey`` and the defaults are used; the failure is
    /// logged.
    static func load(from defaults: UserDefaults) -> BriefSettings {
        guard let data = defaults.data(forKey: defaultsKey) else { return BriefSettings() }
        do {
            return try JSONDecoder().decode(BriefSettings.self, from: data)
        } catch {
            EagarLog(.app).error("brief settings unreadable; kept a backup and using defaults")
            defaults.set(data, forKey: backupKey)
            defaults.removeObject(forKey: defaultsKey)
            return BriefSettings()
        }
    }

    func save(to defaults: UserDefaults) {
        do {
            defaults.set(try JSONEncoder().encode(self), forKey: Self.defaultsKey)
        } catch {
            EagarLog(.app).error("brief settings could not be saved")
        }
    }
}
