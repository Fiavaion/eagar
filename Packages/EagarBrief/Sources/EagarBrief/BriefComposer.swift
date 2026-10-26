import EagarCalendar
import EagarCore
import Foundation

/// Deterministic brief assembly (FR-BRIEF-01, NFR-PERF-03). No AI, no I/O.
public enum BriefComposer {
    /// - Parameters:
    ///   - events: today's events, already classified by calendar tag. Events on calendars Mark
    ///     excluded from the brief should be filtered out by the caller.
    ///   - deadlines: open deadlines.
    ///   - sources: trials, the subscription summary and keep-in-touch nudges (M2).
    ///   - horizon: how far ahead the deadlines section looks.
    public static func compose(
        slot: BriefSlot,
        now: Date,
        events: [ClassifiedEvent],
        deadlines: [BriefDeadline],
        sources: BriefSources = .none,
        preferences: BriefPreferences = .default,
        calendar: Calendar = .current,
        horizon: TimeInterval = 7 * 86_400
    ) -> Brief {
        let dayStart = calendar.startOfDay(for: now)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86_400)

        let todayItems = events
            .filter { $0.event.end > now && $0.event.start < dayEnd }
            .sorted { ($0.event.isAllDay ? 0 : 1, $0.event.start) < ($1.event.isAllDay ? 0 : 1, $1.event.start) }
            .map { classified in
                BriefItem(
                    id: "event.\(classified.event.id)", kind: .event, title: classified.event.title,
                    start: classified.event.start, end: classified.event.end, isAllDay: classified.event.isAllDay,
                    dataClass: classified.dataClass, actions: [.open, .dismiss]
                )
            }

        let overdue = deadlines.filter { $0.dueAt <= now }.sorted { $0.dueAt < $1.dueAt }
        let upcoming = deadlines.filter { $0.dueAt > now && $0.dueAt <= now.addingTimeInterval(horizon) }.sorted { $0.dueAt < $1.dueAt }

        func deadlineItem(_ deadline: BriefDeadline, overdue: Bool) -> BriefItem {
            BriefItem(
                id: "deadline.\(deadline.id)", kind: .deadline, title: deadline.title,
                start: deadline.dueAt, isAllDay: deadline.isAllDay, dataClass: deadline.dataClass,
                actions: overdue ? [.done, .snooze, .reschedule] : [.done, .snooze, .open]
            )
        }

        let content: [BriefSectionKind: [BriefItem]] = [
            .overdue: overdue.map { deadlineItem($0, overdue: true) },
            .today: todayItems,
            .deadlines: upcoming.map { deadlineItem($0, overdue: false) },
            .trials: trialItems(sources, now: now, calendar: calendar),
            .keepInTouch: nudgeItems(sources.nudges, now: now),
        ]

        let sections = preferences.orderedKinds().compactMap { kind -> BriefSection? in
            guard let items = content[kind], !items.isEmpty else { return nil }
            let limit = preferences.maxItems[kind] ?? items.count
            return BriefSection(kind: kind, items: Array(items.prefix(limit)), hiddenCount: max(0, items.count - limit))
        }
        let id = "brief.\(slot.kind.rawValue).\(Int(dayStart.timeIntervalSince1970))"
        return Brief(id: id, slot: slot, generatedAt: now, sections: sections)
    }

    // MARK: Trials and subscriptions (FR-TRIAL-02, FR-TRIAL-05, FR-TRIAL-06)

    /// The summary first (on the 1st of the month only), then trials whose cancel-by day is
    /// today or within their window, soonest first.
    static func trialItems(_ sources: BriefSources, now: Date, calendar: Calendar) -> [BriefItem] {
        let today = calendar.startOfDay(for: now)
        var items: [BriefItem] = []
        if let summary = sources.subscriptionSummary, calendar.component(.day, from: now) == 1 {
            let month = calendar.dateComponents([.year, .month], from: now)
            items.append(BriefItem(
                id: "subscriptions.summary.\(month.year ?? 0)-\(month.month ?? 0)", kind: .subscriptionSummary,
                title: String(localized: "Subscriptions this month", bundle: .module),
                start: nil, dataClass: summary.dataClass, actions: [.open, .dismiss],
                detail: summaryDetail(summary)
            ))
        }
        let due = sources.trials.compactMap { trial -> (BriefTrial, Date)? in
            let day = calendar.startOfDay(for: trial.cancelBy)
            guard day >= today, let opens = calendar.date(byAdding: .day, value: -trial.windowDays, to: day), opens <= today else { return nil }
            return (trial, day)
        }
        .sorted { ($0.1, $0.0.service, $0.0.id) < ($1.1, $1.0.service, $1.0.id) }
        for (trial, day) in due {
            let price = trial.price.formatted(.currency(code: trial.currencyCode))
            let detail = day == today
                ? String(localized: "Cancel today to avoid being charged \(price)", bundle: .module)
                : String(localized: "Cancel by \(dayText(day, calendar: calendar)) to avoid being charged \(price)", bundle: .module)
            items.append(BriefItem(
                id: "trial.\(trial.id)", kind: .trial, title: trial.service, start: day, isAllDay: true,
                dataClass: trial.dataClass, actions: [.cancelSubscription, .confirmCancelled, .dismiss], detail: detail
            ))
        }
        return items
    }

    static func summaryDetail(_ summary: BriefSubscriptionSummary) -> String {
        let monthly = totalsText(summary.monthlyTotals)
        let active = summary.activeCount
        guard summary.chargeCount > 0 else {
            return String(localized: "Active: \(active), about \(monthly) a month. No charges due this month.", bundle: .module)
        }
        let charges = summary.chargeCount
        let due = totalsText(summary.chargeTotals)
        return String(localized: "Active: \(active), about \(monthly) a month. Charges this month: \(charges), \(due) in total.", bundle: .module)
    }

    /// "€45.97" or "€30.00 and £5.99" (no exchange rates).
    static func totalsText(_ totals: [String: Decimal]) -> String {
        guard !totals.isEmpty else { return 0.formatted(.currency(code: "EUR")) }
        return totals.keys.sorted().map { totals[$0, default: 0].formatted(.currency(code: $0)) }.formatted(.list(type: .and))
    }

    static func dayText(_ day: Date, calendar: Calendar) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .omitted).weekday(.abbreviated).day().month(.abbreviated)
        style.timeZone = calendar.timeZone
        return day.formatted(style)
    }

    // MARK: Keep in touch (FR-PEOPLE-05)

    /// Nudges whose slot has not ended, in slot order.
    static func nudgeItems(_ nudges: [BriefNudge], now: Date) -> [BriefItem] {
        nudges
            .filter { $0.slot.end > now }
            .sorted { ($0.slot.start, $0.id) < ($1.slot.start, $1.id) }
            .map {
                BriefItem(
                    id: $0.id, kind: .nudge, title: $0.title, start: $0.slot.start, end: $0.slot.end,
                    dataClass: $0.dataClass, actions: [.plan, .logContact, .snooze, .changeCadence]
                )
            }
    }
}
