//
//  AlertProps.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 20/05/2026.
//

import Foundation

/// Everything an alert view shows and can do, shared by the popup dialog and every
/// full-screen style: event details plus the dismiss, snooze and open actions.
struct AlertProps {
    let title: String
    let time: String
    let location: String?
    let calendarName: String
    let meetingLink: AlertService.MeetingLink?
    let onDismiss: () -> Void
    let onSnooze: (Int) -> Void
    let onOpenMeeting: () -> Void
    let onOpenInCalendar: () -> Void

    /// Snooze durations in minutes offered in every alert's snooze dropdown.
    static let snoozeDurations = [1, 3, 5, 10, 15, 20, 30]

    /// Snooze length used by the Snooze button itself, the S key, and an alert that is closed
    /// or replaced without the user picking an action.
    static let defaultSnoozeMinutes = 5

    /// Primary action of the Open button: joins the meeting when the event has a link,
    /// otherwise opens the event in Calendar. Either way the alarm stops.
    func openDefault() {
        if meetingLink != nil {
            onOpenMeeting()
        } else {
            onOpenInCalendar()
        }
    }
}
