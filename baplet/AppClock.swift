//
//  AppClock.swift
//  baplet
//

import Foundation

/// The app's notion of "now", used wherever the app decides what is past, current or upcoming.
/// It is the real time, except in demo mode, where it is frozen at 09:55 on a weekday (so the
/// screenshots look the same whenever they are taken) and then advances in real time.
enum AppClock {
    /// When the process started, so the demo clock can advance from its fixed starting point.
    private static let launch = Date()

    /// The demo clock's starting point: today at 09:55 local time, or at the most recent
    /// Friday's 09:55 when today is a weekend day.
    private static let demoStart: Date = {
        let calendar = Calendar.current
        var day = calendar.startOfDay(for: launch)
        while calendar.isDateInWeekend(day) {
            day = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        }
        return calendar.date(bySettingHour: 9, minute: 55, second: 0, of: day) ?? day
    }()

    /// The current time: `Date()` normally, the advancing demo time in demo mode.
    static func now() -> Date {
        guard DemoMode.isEnabled else { return Date() }
        return demoStart.addingTimeInterval(Date().timeIntervalSince(launch))
    }
}
