//
//  AlertPopupView.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import AppKit
import SwiftUI

/// SwiftUI view displayed inside the popup dialog alert panel.
/// Shows event details with dismiss and snooze actions.
/// The snooze button defaults to 5 minutes but offers a dropdown for other durations.
struct AlertPopupView: View {
    let title: String
    let time: String
    let location: String?
    let calendarName: String
    let meetingLink: AlertService.MeetingLink?
    let onDismiss: () -> Void
    let onSnooze: (Int) -> Void
    let onOpenInCalendar: () -> Void

    /// Available snooze durations in minutes.
    private let snoozeDurations = [1, 3, 5, 10, 15, 20, 30]

    var body: some View {
        VStack(spacing: 16) {
            Image("baplet")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)

            Text("Upcoming Event")
                .font(.headline)
                .foregroundStyle(.secondary)

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

                Menu {
                    if let meetingLink {
                        Button {
                            onDismiss()
                            NSWorkspace.shared.open(meetingLink.url)
                        } label: {
                            Label("Dismiss and join \(meetingLink.serviceName)", systemImage: meetingLink.icon)
                        }
                    }

                    Button {
                        onOpenInCalendar()
                    } label: {
                        Label("Dismiss and open in Calendar", systemImage: "calendar")
                    }
                } label: {
                    Text("Dismiss")
                } primaryAction: {
                    onDismiss()
                }
                .controlSize(.large)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(24)
        .frame(width: 320)
    }
}
