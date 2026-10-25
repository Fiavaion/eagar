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
    Use only what the lines say. Keep every time and name exactly as written. \
    Never mention a date, day of the week, month or time that is not in the lines. \
    Do not add places, people or details.
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
                    let source = request.inputs.map(\.text).joined(separator: "\n")
                    guard isFaithful(response.text, to: source) else {
                        EagarLog(.ai).notice("brief phrasing for \(section.kind) discarded: it added dates or numbers")
                        continue
                    }
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

    /// Whether `output` stays within `source`: every number, weekday and month name it mentions
    /// must appear in the source lines. Models invent dates and times (an all-day event became
    /// "Saturday, 21st May, at 10:00 am" in testing); any such sentence is discarded and the
    /// deterministic brief is shown instead.
    static func isFaithful(_ output: String, to source: String) -> Bool {
        let sourceLower = source.lowercased()
        let sourceNumbers = Set(numbers(in: source))
        guard numbers(in: output).allSatisfy(sourceNumbers.contains) else { return false }
        let words = output.lowercased().split { !$0.isLetter }.map(String.init)
        return words.allSatisfy { word in
            !calendarWords.contains(word) || sourceLower.contains(word)
        }
    }

    /// Runs of digits, e.g. "09:30" gives ["09", "30"]; "21st" gives ["21"].
    static func numbers(in text: String) -> [String] {
        text.split { !$0.isNumber }.map { run in
            let trimmed = run.drop { $0 == "0" }
            return trimmed.isEmpty ? "0" : String(trimmed)
        }
    }

    /// Weekday and month names (English, as the prompt asks for British English).
    static let calendarWords: Set<String> = {
        let english = Locale(identifier: "en_GB")
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = english
        let names = calendar.weekdaySymbols + calendar.shortWeekdaySymbols + calendar.monthSymbols + calendar.shortMonthSymbols
        // "May" is also a common verb; a "21st May" is still caught by its number. Relative days
        // and parts of the day are checked too, because a model invents those as readily.
        return Set(names.map { $0.lowercased() }).subtracting(["may"]).union([
            "noon", "midnight", "today", "tomorrow", "yesterday", "tonight", "morning", "afternoon",
            "evening", "weekend", "week", "fortnight", "month",
        ])
    }()

    /// One input line: time and title. Times use the brief's calendar time zone; all-day items
    /// say so, so the model has no reason to invent a time.
    static func line(for item: BriefItem, calendar: Calendar) -> String {
        guard let start = item.start, !item.isAllDay else { return "All day: \(item.title)" }
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = calendar.timeZone
        return "\(start.formatted(style)) \(item.title)"
    }
}
