//
//  WorkingHours.swift
//  baplet
//

import Foundation

/// The time window and days when Baplet alerts by default. Meetings that start outside it
/// stay quiet (no alert, no menu bar countdown) unless switched on one by one. Off by default,
/// so nothing changes until the user turns it on.
struct WorkingHours: Equatable {
    /// Whether working hours apply at all; when false every time counts as working time.
    var isEnabled: Bool

    /// Start of the window, in minutes after midnight (e.g. 480 for 08:00).
    var startMinutes: Int

    /// End of the window, in minutes after midnight; a meeting starting exactly then is outside.
    var endMinutes: Int

    /// Working days as `Calendar` weekday numbers (1 = Sunday … 7 = Saturday).
    var weekdays: Set<Int>

    /// What working hours start as when first turned on: Monday to Friday, 08:00–16:00.
    static let standard = WorkingHours(isEnabled: false, startMinutes: 8 * 60, endMinutes: 16 * 60, weekdays: [2, 3, 4, 5, 6])

    /// Whether `date` falls inside working hours: on a working day and at or after the start
    /// but before the end. Always true while working hours are off. A window whose end is not
    /// after its start (e.g. 22:00–06:00) runs past midnight, counted on the day it starts.
    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        guard isEnabled else { return true }
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: date)
        guard let weekday = parts.weekday, let hour = parts.hour, let minute = parts.minute else { return true }
        let minutes = hour * 60 + minute
        if startMinutes < endMinutes {
            return weekdays.contains(weekday) && minutes >= startMinutes && minutes < endMinutes
        }
        if minutes >= startMinutes {
            return weekdays.contains(weekday)
        }
        let previousDay = weekday == 1 ? 7 : weekday - 1
        return weekdays.contains(previousDay) && minutes < endMinutes
    }

    /// The window as clock times in the user's style, e.g. "08:00–16:00", for help texts.
    func timeRangeText(calendar: Calendar = .current) -> String {
        "\(Self.clockText(startMinutes, calendar: calendar))–\(Self.clockText(endMinutes, calendar: calendar))"
    }

    /// One time of day (minutes after midnight) as a short clock time.
    private static func clockText(_ minutes: Int, calendar: Calendar) -> String {
        let day = calendar.startOfDay(for: Date())
        let date = calendar.date(byAdding: .minute, value: minutes, to: day) ?? day
        return EventTimeFormat.time(date)
    }
}

/// How long before a meeting the menu bar starts counting down to it.
enum CountdownRange: String, CaseIterable, Identifiable {
    case withAlert
    case minutes15
    case minutes30
    case hour1
    case hours2
    case allDay

    /// Identity for `ForEach` and pickers: the stored raw value.
    var id: String { rawValue }

    /// Label for the Settings picker.
    var label: String {
        switch self {
        case .withAlert: "With the alert"
        case .minutes15: "15 minutes before"
        case .minutes30: "30 minutes before"
        case .hour1: "1 hour before"
        case .hours2: "2 hours before"
        case .allDay: "All day"
        }
    }

    /// How many minutes ahead the countdown shows, given the alert lead time; nil for all day,
    /// where any later meeting today counts.
    func minutesAhead(alertLeadMinutes: Int) -> Int? {
        switch self {
        case .withAlert: alertLeadMinutes
        case .minutes15: 15
        case .minutes30: 30
        case .hour1: 60
        case .hours2: 120
        case .allDay: nil
        }
    }
}
