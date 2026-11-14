//
//  AlertPopupView.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import AppKit
import SwiftUI

/// SwiftUI view displayed inside the popup dialog alert panel.
/// Shows event details with snooze, dismiss and open actions.
/// Snooze defaults to 5 minutes with a dropdown for other durations; Open joins the meeting
/// (or opens Calendar when there is no link) and offers both choices in its dropdown.
struct AlertPopupView: View {
    let title: String
    let time: String
    let location: String?
    let calendarName: String
    let meetingLink: AlertService.MeetingLink?
    let onDismiss: () -> Void
    let onSnooze: (Int) -> Void
    let onOpenMeeting: () -> Void
    let onOpenInCalendar: () -> Void

    /// Available snooze durations in minutes.
    private let snoozeDurations = [1, 3, 5, 10, 15, 20, 30]

    var body: some View {
        VStack(spacing: 16) {
            Image("baplet")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)

            VStack(spacing: 6) {
                Text(title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(time)
                    .font(.body)
                    .foregroundStyle(.secondary)

                if let location, !location.isEmpty {
                    Label(location, systemImage: "location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(calendarName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Menu {
                    ForEach(snoozeDurations, id: \.self) { minutes in
                        Button("\(minutes) min") { onSnooze(minutes) }
                    }
                } label: {
                    Text("Snooze 5m")
                } primaryAction: {
                    onSnooze(5)
                }
                .controlSize(.large)

                Button("Dismiss") { onDismiss() }
                    .controlSize(.large)

                openButton
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 320)
    }

    /// Open button: with a meeting link, a click joins the meeting and the dropdown offers
    /// "Open meeting" and "Open calendar"; without one, it is a plain button that opens Calendar.
    @ViewBuilder
    private var openButton: some View {
        if let meetingLink {
            Menu {
                Button {
                    onOpenMeeting()
                } label: {
                    Label("Open meeting", systemImage: meetingLink.icon)
                }
                Button {
                    onOpenInCalendar()
                } label: {
                    Label("Open calendar", systemImage: "calendar")
                }
            } label: {
                Text("Open")
            } primaryAction: {
                onOpenMeeting()
            }
        } else {
            Button("Open") { onOpenInCalendar() }
        }
    }
}
