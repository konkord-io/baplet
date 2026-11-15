//
//  WorkingHoursTests.swift
//  bapletTests
//

import Foundation
import Testing
@testable import Baplet

/// Tests for `WorkingHours` and `CountdownRange`, on a fixed UTC calendar so the results don't
/// depend on the machine's time zone.
struct WorkingHoursTests {
    /// Gregorian calendar in UTC used for every date in these tests.
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Monday to Friday, 08:00–16:00, switched on.
    let office = WorkingHours(isEnabled: true, startMinutes: 8 * 60, endMinutes: 16 * 60, weekdays: [2, 3, 4, 5, 6])

    /// A date in November 2026 (the 18th is a Wednesday) at the given time.
    func date(day: Int, hour: Int, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    /// Checks that switched-off working hours contain every time.
    @Test
    func disabledContainsEverything() {
        var hours = office
        hours.isEnabled = false
        #expect(hours.contains(date(day: 21, hour: 3), calendar: calendar))
    }

    /// Checks the window's edges on a working day: start inside, end outside.
    @Test
    func windowEdgesOnWorkingDay() {
        #expect(office.contains(date(day: 18, hour: 8), calendar: calendar))
        #expect(office.contains(date(day: 18, hour: 15, minute: 59), calendar: calendar))
        #expect(!office.contains(date(day: 18, hour: 7, minute: 59), calendar: calendar))
        #expect(!office.contains(date(day: 18, hour: 16), calendar: calendar))
    }

    /// Checks that days that aren't working days are outside, whatever the time.
    @Test
    func weekendIsOutside() {
        #expect(!office.contains(date(day: 21, hour: 10), calendar: calendar))
        #expect(!office.contains(date(day: 22, hour: 10), calendar: calendar))
    }

    /// Checks a window past midnight, which belongs to the day it starts on.
    @Test
    func overnightWindowBelongsToStartDay() {
        let night = WorkingHours(isEnabled: true, startMinutes: 22 * 60, endMinutes: 6 * 60, weekdays: [6])
        #expect(night.contains(date(day: 20, hour: 23), calendar: calendar))
        #expect(night.contains(date(day: 21, hour: 2), calendar: calendar))
        #expect(!night.contains(date(day: 22, hour: 2), calendar: calendar))
        #expect(!night.contains(date(day: 20, hour: 12), calendar: calendar))
    }

    /// Checks how far ahead each countdown choice reaches.
    @Test
    func countdownRangeMinutes() {
        #expect(CountdownRange.withAlert.minutesAhead(alertLeadMinutes: 7) == 7)
        #expect(CountdownRange.minutes15.minutesAhead(alertLeadMinutes: 7) == 15)
        #expect(CountdownRange.hours2.minutesAhead(alertLeadMinutes: 7) == 120)
        #expect(CountdownRange.allDay.minutesAhead(alertLeadMinutes: 7) == nil)
    }
}
