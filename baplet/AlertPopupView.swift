//
//  AlertPopupView.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import SwiftUI

/// SwiftUI view displayed inside the popup dialog alert panel.
/// Shows event details with snooze, dismiss and open actions.
/// Snooze uses the default time with a dropdown for other durations; Open joins the meeting
/// (or opens Calendar when there is no link) and offers both choices in its dropdown.
struct AlertPopupView: View {
    let props: AlertProps

    var body: some View {
        VStack(spacing: 16) {
            Image("goldfish")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(height: 200)

            VStack(spacing: 6) {
                Text(props.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)

                Text(props.time)
                    .font(.body)
                    .foregroundStyle(.secondary)

                if let location = props.location, !location.isEmpty {
                    Label(location, systemImage: "location")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Text(props.calendarName)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            HStack(spacing: 12) {
                Menu {
                    ForEach(AlertProps.snoozeDurations, id: \.self) { minutes in
                        Button("\(minutes) min") { props.onSnooze(minutes) }
                    }
                } label: {
                    Text("Snooze \(AlertProps.defaultSnoozeMinutes)m")
                } primaryAction: {
                    props.onSnooze(AlertProps.defaultSnoozeMinutes)
                }
                .controlSize(.large)

                Button("Dismiss") { props.onDismiss() }
                    .controlSize(.large)

                openButton
                    .controlSize(.large)
            }
        }
        .padding(24)
        .frame(width: 380)
    }

    /// Open button: with a meeting link, a click joins the meeting and the dropdown offers
    /// "Open meeting" and "Open calendar"; without one, it is a plain button that opens Calendar.
    @ViewBuilder
    private var openButton: some View {
        if let meetingLink = props.meetingLink {
            Menu {
                Button {
                    props.onOpenMeeting()
                } label: {
                    Label("Open meeting", systemImage: meetingLink.icon)
                }
                Button {
                    props.onOpenInCalendar()
                } label: {
                    Label("Open calendar", systemImage: "calendar")
                }
            } label: {
                Text("Open")
            } primaryAction: {
                props.onOpenMeeting()
            }
        } else {
            Button("Open") { props.onOpenInCalendar() }
        }
    }
}
