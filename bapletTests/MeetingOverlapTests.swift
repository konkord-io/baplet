//
//  MeetingOverlapTests.swift
//  bapletTests
//

import Foundation
import Testing
@testable import Baplet

/// Tests for `MeetingOverlap.overlapping`, which decides which meetings an alert warns about.
struct MeetingOverlapTests {
    /// A slot from `startMinute` to `endMinute` minutes after a fixed reference time.
    func slot(_ key: String, _ startMinute: Int, _ endMinute: Int) -> MeetingOverlap.Slot {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        return MeetingOverlap.Slot(
            key: key,
            start: base.addingTimeInterval(TimeInterval(startMinute * 60)),
            end: base.addingTimeInterval(TimeInterval(endMinute * 60))
        )
    }

    /// Checks that meetings overlapping by any amount are listed, sorted by start, and that
    /// the target itself, meetings that only touch it and meetings elsewhere in the day are not.
    @Test
    func listsMeetingsOverlappingByAnyAmount() {
        let target = slot("a", 0, 60)
        let all = [
            target,
            slot("late", 30, 45),
            slot("same", 0, 30),
            slot("before", -30, 5),
            slot("touchesEnd", 60, 90),
            slot("touchesStart", -30, 0),
            slot("later", 120, 150),
        ]
        #expect(MeetingOverlap.overlapping(target, in: all).map(\.key) == ["before", "same", "late"])
    }

    /// Checks that a long meeting surrounding the target counts as overlapping.
    @Test
    func surroundingMeetingOverlaps() {
        let target = slot("a", 30, 45)
        #expect(MeetingOverlap.overlapping(target, in: [target, slot("day", 0, 480)]).map(\.key) == ["day"])
    }

    /// Checks that a meeting with nothing else at the same time has no overlaps.
    @Test
    func noOverlapsWhenAlone() {
        let target = slot("a", 0, 30)
        #expect(MeetingOverlap.overlapping(target, in: [target, slot("b", 30, 60)]).isEmpty)
    }
}
