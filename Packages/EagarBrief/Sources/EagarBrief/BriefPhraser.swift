import EagarAI
import EagarCore
import Foundation

/// How the brief may be phrased by AI (FR-BRIEF-04). The deterministic brief is always shown;
/// phrasing only adds a friendlier sentence per section.
public enum BriefPhrasingMode: String, Sendable, Codable, CaseIterable {
    /// No AI.
    case off
    /// On-device or Mac models only, for every section.
    case localOnly
    /// Personal and public items may go to Claude (with consent); college items stay local.
    case claudeForPersonal
}

/// A phrased section: one part per data-class group, merged in display order.
public struct PhrasedSection: Sendable, Hashable {
    public struct Part: Sendable, Hashable {
        public let text: String
        public let tier: Tier?
        public let isCollege: Bool
    }

    public let kind: BriefSectionKind
    public let parts: [Part]
    public var text: String { parts.map(\.text).joined(separator: " ") }
}

/// Phrases brief sections through the AI router.
///
/// College items and other items in the same section are sent as **separate** requests, so a
/// cloud request never carries a college line (B-6). The router independently refuses to send
/// college data off-device; this split is what lets personal lines still use Claude.
public enum BriefPhraser {
    static let instruction = """
    Rewrite these calendar and deadline lines as one short, calm sentence in British English. \
    Keep every time and name exactly as given. Do not add anything.
    """

    public static func phrase(_ brief: Brief, mode: BriefPhrasingMode, router: AIRouter, calendar: Calendar = .current) async -> [BriefSectionKind: PhrasedSection] {
        guard mode != .off else { return [:] }
        var result: [BriefSectionKind: PhrasedSection] = [:]
        for section in brief.sections where !section.items.isEmpty {
            var parts: [PhrasedSection.Part] = []
            let groups = [
                (isCollege: false, items: section.items.filter { $0.dataClass != .college }),
                (isCollege: true, items: section.items.filter { $0.dataClass == .college }),
            ]
            for group in groups where !group.items.isEmpty {
                let preferred: Tier? = (mode == .claudeForPersonal && !group.isCollege) ? .anthropicCloud : nil
                let request = AIRequest(
                    purpose: .briefPhrase,
                    inputs: group.items.map { ClassifiedPayload(line(for: $0, calendar: calendar), dataClass: $0.dataClass, kind: .derivedItem) },
                    system: ClassifiedPayload(instruction, dataClass: .publicContent),
                    preferredTier: preferred,
                    maxOutputTokens: 200
                )
                do {
                    let response = try await router.run(request)
                    guard response.stopReason != .refusal, !response.text.isEmpty else { continue }
                    parts.append(.init(text: response.text, tier: response.tier, isCollege: group.isCollege))
                } catch {
                    // Phrasing is optional: the deterministic section stays as it is.
                    EagarLog(.ai).notice("brief phrasing skipped for \(section.kind): \(error)")
                }
            }
            if !parts.isEmpty { result[section.kind] = PhrasedSection(kind: section.kind, parts: parts) }
        }
        return result
    }

    /// One input line: time and title. Times use the brief's calendar time zone.
    static func line(for item: BriefItem, calendar: Calendar) -> String {
        guard let start = item.start, !item.isAllDay else { return item.title }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        return "\(start.formatted(style)) \(item.title)"
    }
}
