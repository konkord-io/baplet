//
//  TestHelpers.swift
//  bapletTests
//

import EventKit
import Foundation

/// Builds an in-memory `EKEvent` for tests. It needs no calendar access, so the tests run
/// the same on any machine; only the fields the code under test reads are set.
func makeEvent(
    id: String? = nil,
    title: String? = "Event",
    start: Date = Date(timeIntervalSince1970: 1_800_000_000),
    duration: TimeInterval = 3600,
    allDay: Bool = false,
    url: URL? = nil,
    location: String? = nil,
    notes: String? = nil
) -> EKEvent {
    let event = EKEvent(eventStore: EKEventStore())
    event.title = title
    event.startDate = start
    event.endDate = start.addingTimeInterval(duration)
    event.isAllDay = allDay
    event.url = url
    event.location = location
    event.notes = notes
    return event
}
