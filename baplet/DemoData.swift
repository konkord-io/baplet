//
//  DemoData.swift
//  baplet
//

import EventKit
import Foundation

/// Sample calendars and events for demo mode, built in memory (never saved to EventKit) with
/// neutral titles, and dated relative to the app clock so the screenshots always look current.
enum DemoData {
    /// Title of the event that starts in a few minutes; also used by the sample alert.
    static let standUpTitle = "Team stand-up"

    /// Start of the stand-up: 10:00 on the demo clock's day, five minutes after it starts.
    static var standUpStart: Date {
        let now = AppClock.now()
        return Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: now) ?? now
    }

    /// Builds the Work, Personal and Team calendars, attached to a real source when EventKit
    /// offers one so the Settings list can group them.
    static func makeCalendars(store: EKEventStore) -> [EKCalendar] {
        let source = store.defaultCalendarForNewEvents?.source ?? store.sources.first
        let specs: [(title: String, color: CGColor)] = [
            ("Work", CGColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1)),
            ("Personal", CGColor(red: 0.20, green: 0.70, blue: 0.40, alpha: 1)),
            ("Team", CGColor(red: 0.95, green: 0.55, blue: 0.15, alpha: 1)),
        ]
        return specs.map { spec in
            let calendar = EKCalendar(for: .event, eventStore: store)
            calendar.title = spec.title
            calendar.cgColor = spec.color
            if let source { calendar.source = source }
            return calendar
        }
    }

    /// Builds today's and tomorrow's sample events in the given calendars (Work, Personal, Team
    /// in that order), including one that has already ended and one all-day event.
    static func makeEvents(store: EKEventStore, calendars: [EKCalendar]) -> [EKEvent] {
        let cal = Calendar.current
        let now = AppClock.now()
        let today = cal.startOfDay(for: now)
        let tomorrow = cal.date(byAdding: .day, value: 1, to: today) ?? today.addingTimeInterval(86_400)

        /// Returns `base` moved to the given hour and minute.
        func at(_ base: Date, _ hour: Int, _ minute: Int = 0) -> Date {
            cal.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        /// Builds one event; `minutes` is its length.
        func make(
            _ title: String, _ calendar: EKCalendar, start: Date, minutes: Int,
            allDay: Bool = false, location: String? = nil, notes: String? = nil
        ) -> EKEvent {
            let event = EKEvent(eventStore: store)
            event.calendar = calendar
            event.title = title
            event.isAllDay = allDay
            event.startDate = start
            event.endDate = allDay ? start : start.addingTimeInterval(TimeInterval(minutes * 60))
            event.location = location
            event.notes = notes
            return event
        }

        let work = calendars[0], personal = calendars[1], team = calendars[2]
        return [
            make("Release day", team, start: today, minutes: 0, allDay: true),
            make("Coffee with Sam", personal, start: at(today, 9), minutes: 30, location: "Corner Cafe"),
            make(standUpTitle, work, start: standUpStart, minutes: 15,
                 notes: "Join: https://meet.google.com/abc-defg-hij"),
            make("Design review", work, start: at(today, 14), minutes: 60,
                 notes: "Join: https://zoom.us/j/123456789"),
            make("Gym", personal, start: at(today, 18), minutes: 60, location: "Fitness Studio"),
            make("Planning", team, start: at(tomorrow, 9, 30), minutes: 45, location: "Room 4"),
            make("Lunch with Alex", personal, start: at(tomorrow, 12), minutes: 60, location: "Market Hall"),
            make("Sprint demo", work, start: at(tomorrow, 14), minutes: 30,
                 notes: "Join: https://meet.google.com/xyz-abcd-efg"),
        ]
    }
}
