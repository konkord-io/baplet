//
//  FullScreenAlertProps.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 20/05/2026.
//

import Foundation

/// Shared data passed to all full-screen alert style views.
/// Contains event details, action callbacks, and snooze configuration.
struct FullScreenAlertProps {
    let title: String
    let time: String
    let location: String?
    let calendarName: String
    let meetingLink: AlertService.MeetingLink?
    let onDismiss: () -> Void
    let onSnooze: (Int) -> Void
    let onOpenInCalendar: () -> Void

    /// Available snooze durations in minutes offered in the dropdown.
    let snoozeDurations: [Int] = [1, 3, 5, 10, 15, 20, 30]
}
