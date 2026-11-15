//
//  MenuBarStatusTests.swift
//  bapletTests
//

import EventKit
import Foundation
import Testing
@testable import Baplet

/// Tests for `MenuBarStatus.compute` and the countdown text, with a fixed "now" and a UTC
/// calendar so "today" is the same on every machine.
struct MenuBarStatusTests {
    /// Gregorian calendar in UTC.
    let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    /// Wednesday 18 November 2026, 10:00 UTC.
    var now: Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: 18, hour: 10))!
    }

    /// A one-hour timed event starting `minutes` from `now`.
    func event(_ minutes: Double, title: String = "Event", duration: TimeInterval = 3600) -> EKEvent {
        makeEvent(title: title, start: now.addingTimeInterval(minutes * 60), duration: duration)
    }

    /// Runs `compute` with a 5-minute alert lead and every alarm on unless told otherwise.
    func status(
        _ events: [EKEvent],
        countdownMinutes: Int? = nil,
        paused: Bool = false,
        isAlarmEnabled: @escaping (EKEvent) -> Bool = { _ in true }
    ) -> MenuBarStatus {
        MenuBarStatus.compute(
            events: events,
            now: now,
            isPaused: paused,
            alertLeadMinutes: 5,
            countdownMinutes: countdownMinutes,
            isAlarmEnabled: isAlarmEnabled,
            calendar: calendar
        )
    }

    /// Checks the countdown text under an hour, on the hour and with hours and minutes.
    @Test
    func countdownText() {
        #expect(MenuBarStatus.countdownText(minutes: 3) == "3m")
        #expect(MenuBarStatus.countdownText(minutes: 60) == "1h")
        #expect(MenuBarStatus.countdownText(minutes: 94) == "1h34m")
        #expect(MenuBarStatus.countdownText(minutes: 120) == "2h")
    }

    /// Checks that paused alarms win over everything else, and that no events means idle.
    @Test
    func pausedAndIdle() {
        #expect(status([event(10)], paused: true) == .paused)
        #expect(status([]) == .idle)
    }

    /// Checks that with "all day" any later meeting today gets the countdown.
    @Test
    func allDayCountsDownToNextMeetingToday() {
        #expect(status([event(94)]) == .upcoming(minutesLeft: 94))
        #expect(status([event(94)]).label == "1h34m")
    }

    /// Checks that tomorrow's meetings never get the countdown.
    @Test
    func tomorrowIsIgnored() {
        #expect(status([event(15 * 60)]) == .idle)
    }

    /// Checks that a limited range only counts down once the meeting is close enough.
    @Test
    func limitedRange() {
        #expect(status([event(45)], countdownMinutes: 30) == .idle)
        #expect(status([event(20)], countdownMinutes: 30) == .upcoming(minutesLeft: 20))
    }

    /// Checks NOW during a meeting, and that a next meeting within the alert lead time takes
    /// over from NOW.
    @Test
    func runningMeeting() {
        let running = event(-30)
        #expect(status([running, event(40)]) == .active)
        #expect(status([running, event(3)]) == .upcoming(minutesLeft: 3))
    }

    /// Checks that all-day events and events whose alarm is off don't count.
    @Test
    func skipsAllDayAndAlarmOff() {
        let holiday = makeEvent(title: "Holiday", start: now, allDay: true)
        let quiet = event(10, title: "quiet")
        #expect(status([holiday]) == .idle)
        #expect(status([quiet, event(50)], isAlarmEnabled: { $0.title != "quiet" }) == .upcoming(minutesLeft: 50))
    }
}
