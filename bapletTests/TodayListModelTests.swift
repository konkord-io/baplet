//
//  TodayListModelTests.swift
//  bapletTests
//

import EventKit
import Foundation
import Testing
@testable import Baplet

/// Tests for `TodayListModel`, the selection state behind the Today panel.
struct TodayListModelTests {
    /// A fixed "current time" so selection does not depend on the real clock.
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    /// Builds a one-hour event starting `offset` seconds from `now`.
    func event(_ offset: TimeInterval, title: String, allDay: Bool = false) -> EKEvent {
        makeEvent(title: title, start: now.addingTimeInterval(offset), allDay: allDay)
    }

    /// Checks that events that have ended are left out, while the one running now, upcoming
    /// ones and all-day events stay, matching what the menu lists.
    @Test
    func dropsEndedEvents() {
        let events = [
            event(-1800, title: "holiday", allDay: true),
            event(-7200, title: "past"),
            event(-600, title: "now"),
            event(3600, title: "next"),
        ]
        let model = TodayListModel(events: events, now: now)
        #expect(model.events.map(\.title) == ["holiday", "now", "next"])
    }

    /// Checks that the event running now is preselected over a later one.
    @Test
    func selectsMeetingHappeningNow() {
        let events = [event(-7200, title: "past"), event(-600, title: "now"), event(3600, title: "next")]
        let model = TodayListModel(events: events, now: now)
        #expect(model.selectedEvent?.title == "now")
    }

    /// Checks that, with nothing running, the next upcoming event is preselected.
    @Test
    func selectsNextWhenNothingRunning() {
        let events = [event(-7200, title: "past"), event(1800, title: "next"), event(9000, title: "later")]
        let model = TodayListModel(events: events, now: now)
        #expect(model.selectedEvent?.title == "next")
    }

    /// Checks that all-day events are never the starting selection.
    @Test
    func skipsAllDayEvents() {
        let events = [event(-1800, title: "holiday", allDay: true), event(1800, title: "call")]
        let model = TodayListModel(events: events, now: now)
        #expect(model.selectedIndex == 1)
        #expect(model.selectedEvent?.title == "call")
    }

    /// Checks that once every meeting has ended the list is empty and nothing is selected.
    @Test
    func emptyWhenAllEnded() {
        let events = [event(-20000, title: "a"), event(-10000, title: "b")]
        let model = TodayListModel(events: events, now: now)
        #expect(model.events.isEmpty)
        #expect(model.selectedIndex == nil)
    }

    /// Checks that an all-day event is selected when it is the only thing left today.
    @Test
    func selectsAllDayWhenOnlyOneLeft() {
        let events = [event(-1800, title: "holiday", allDay: true), event(-10000, title: "done")]
        let model = TodayListModel(events: events, now: now)
        #expect(model.selectedEvent?.title == "holiday")
    }

    /// Checks that an empty list has no selection and that moving does nothing.
    @Test
    func emptyListHasNoSelection() {
        let model = TodayListModel(events: [], now: now)
        #expect(model.selectedIndex == nil)
        #expect(model.selectedEvent == nil)
        model.move(by: 1)
        #expect(model.selectedIndex == nil)
    }

    /// Checks that `move(by:)` stops at both the first and the last event instead of wrapping.
    @Test
    func moveStopsAtEnds() {
        let events = [event(-600, title: "a"), event(1800, title: "b"), event(3600, title: "c")]
        let model = TodayListModel(events: events, now: now)
        model.move(by: 1)
        model.move(by: 1)
        #expect(model.selectedIndex == 2)
        model.move(by: 1)
        #expect(model.selectedIndex == 2)
        model.move(by: -1)
        model.move(by: -1)
        #expect(model.selectedIndex == 0)
        model.move(by: -1)
        #expect(model.selectedIndex == 0)
    }
}
