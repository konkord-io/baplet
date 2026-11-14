//
//  CalendarEventRow.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import AppKit
import EventKit
import SwiftUI

/// A row view displaying a single calendar event with its title, time range,
/// optional location, and a color indicator matching the event's calendar.
/// Includes a context menu for toggling alarm notifications per event.
struct CalendarEventRow: View {
    let event: EKEvent

    @Environment(SettingsStore.self) private var settingsStore
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(cgColor: event.calendar.cgColor))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title ?? "No Title")
                    .font(.headline)

                if event.isAllDay {
                    Text("All Day")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(timeRange)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if let meetingLink = AlertService.extractMeetingLink(from: event) {
                Button {
                    NSWorkspace.shared.open(meetingLink.url)
                } label: {
                    Image(systemName: meetingLink.icon)
                        .font(.subheadline)
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
                .help("Join \(meetingLink.serviceName)")
            }

            if !event.isAllDay {
                Button {
                    settingsStore.toggleEventAlarm(eventID: event.eventIdentifier)
                } label: {
                    if settingsStore.isAlarmEnabled(eventID: event.eventIdentifier) {
                        Image(systemName: "bell.fill")
                            .font(.subheadline)
                            .foregroundStyle(.green)
                    } else {
                        Image(systemName: "bell.slash.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red.opacity(0.7))
                    }
                }
                .buttonStyle(.borderless)
                .help(settingsStore.isAlarmEnabled(eventID: event.eventIdentifier) ? "Disable alarm" : "Enable alarm")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(isHovered ? Color.primary.opacity(0.1) : Color.clear)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
        .onTapGesture {
            openInCalendar()
        }
    }

    /// Opens this event in Apple Calendar via a temporary .ics file.
    private func openInCalendar() {
        AlertService.openEventInCalendar(
            title: event.title ?? "No Title",
            startDate: event.startDate,
            endDate: event.endDate,
            uid: event.calendarItemExternalIdentifier
        )
    }

    /// Formats the event's start and end time into a readable range string.
    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return "\(formatter.string(from: event.startDate)) \u{2013} \(formatter.string(from: event.endDate))"
    }
}
