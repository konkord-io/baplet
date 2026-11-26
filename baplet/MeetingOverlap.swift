//
//  MeetingOverlap.swift
//  baplet
//

import CoreGraphics
import Foundation

/// Finds the meetings that clash with the one an alert is for, so the alert can warn about
/// them and joining one can hold the others until it ends.
enum MeetingOverlap {
    /// One meeting's time slot, identified by its `EKEvent.alarmKey`.
    struct Slot: Equatable {
        let key: String
        let start: Date
        let end: Date
    }

    /// Returns the slots, other than `target` itself, whose time overlaps `target`'s by any
    /// amount, sorted by start. Meetings that only touch (one ends as the other starts) don't
    /// overlap.
    static func overlapping(_ target: Slot, in slots: [Slot]) -> [Slot] {
        slots
            .filter { $0.key != target.key && $0.start < target.end && $0.end > target.start }
            .sorted { $0.start < $1.start }
    }
}

/// An overlapping meeting as listed in an alert: what it is and when.
struct OverlappingMeeting: Identifiable {
    let id: String
    let title: String
    let timeRange: String
    let calendarColor: CGColor?
}
