import Foundation

/// Deterministic brief text for a nudge (FR-PEOPLE-05): "Thursday evening is free; Aoife: 7 weeks".
///
/// Built from String Catalog entries, never by concatenating sentences.
public enum NudgePhrasing {
    public enum DayPart: String, Sendable, Hashable, CaseIterable {
        case morning, afternoon, evening

        /// Before 12:00 is morning, before 17:00 afternoon, otherwise evening.
        public static func of(_ date: Date, calendar: Calendar) -> DayPart {
            switch calendar.component(.hour, from: date) {
            case ..<12: .morning
            case ..<17: .afternoon
            default: .evening
            }
        }
    }

    /// The whole line for the brief.
    public static func text(for nudge: Nudge, calendar: Calendar, locale: Locale = .current) -> String {
        let when = slotText(nudge.slot.start, calendar: calendar, locale: locale)
        let since = sinceText(daysSince: nudge.daysSince)
        let name = nudge.displayName
        return String(localized: "\(when) is free; \(name): \(since)", bundle: .module, locale: locale, comment: "Keep-in-touch nudge: slot, person, time since last contact")
    }

    /// "Thursday evening".
    public static func slotText(_ date: Date, calendar: Calendar, locale: Locale = .current) -> String {
        var style = Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
        style = style.weekday(.wide)
        let weekday = date.formatted(style)
        switch DayPart.of(date, calendar: calendar) {
        case .morning: return String(localized: "\(weekday) morning", bundle: .module, locale: locale, comment: "Weekday name, then part of day")
        case .afternoon: return String(localized: "\(weekday) afternoon", bundle: .module, locale: locale, comment: "Weekday name, then part of day")
        case .evening: return String(localized: "\(weekday) evening", bundle: .module, locale: locale, comment: "Weekday name, then part of day")
        }
    }

    /// "7 weeks", "5 days" or "no contact yet".
    public static func sinceText(daysSince: Int?, locale: Locale = .current) -> String {
        guard let days = daysSince else {
            return String(localized: "no contact yet", bundle: .module, locale: locale, comment: "Keep-in-touch: no interaction known")
        }
        if days >= 7 {
            let weeks = days / 7
            return String(localized: "\(weeks) weeks", bundle: .module, locale: locale, comment: "Weeks since last contact")
        }
        return String(localized: "\(days) days", bundle: .module, locale: locale, comment: "Days since last contact")
    }
}
