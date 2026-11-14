//
//  EventAlarmKeyTests.swift
//  bapletTests
//

import Foundation
import Testing
@testable import Baplet

/// Tests for `EventAlarmKey` and `EKEvent.alarmKey`, the per-occurrence alarm identifiers.
struct EventAlarmKeyTests {
    /// Checks that a made key yields its start date back (to whole seconds), including an
    /// event identifier that itself contains ":" and "@".
    @Test
    func roundTrip() {
        let start = Date(timeIntervalSince1970: 1_800_000_123)
        let key = EventAlarmKey.make(eventID: "ABC:def@x|y", start: start)
        #expect(EventAlarmKey.startDate(of: key) == start)
    }

    /// Checks that keys not in the `<id>|<seconds>` format give nil, so stale or foreign
    /// entries are recognised.
    @Test(arguments: ["", "no-separator", "id|", "id|notanumber", "id|12.5"])
    func malformedKeysGiveNil(key: String) {
        #expect(EventAlarmKey.startDate(of: key) == nil)
    }

    /// Checks that two occurrences of one event id at different starts get different keys, so
    /// switching off one occurrence leaves the rest of a series alone.
    @Test
    func occurrencesGetDistinctKeys() {
        let first = EventAlarmKey.make(eventID: "series", start: Date(timeIntervalSince1970: 1_800_000_000))
        let second = EventAlarmKey.make(eventID: "series", start: Date(timeIntervalSince1970: 1_800_086_400))
        #expect(first != second)
    }

    /// Checks that an unsaved event has no identifier and therefore no alarm key.
    @Test
    func unsavedEventHasNoAlarmKey() {
        #expect(makeEvent().alarmKey == nil)
    }
}
