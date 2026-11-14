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
            .opacity(isDimmed ? 0.45 : 1)
            .animation(.easeOut(duration: 0.15), value: isDimmed)

            Spacer()

            if let meetingLink = AlertService.extractMeetingLink(from: event) {
                Button {
                    BrowserService.openMeeting(meetingLink.url, settings: settingsStore)
                } label: {
                    Image(systemName: meetingLink.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.borderless)
                .help("Join \(meetingLink.serviceName)")
            }

            if !event.isAllDay {
                Toggle("Alarm", isOn: alarmEnabled)
                    .toggleStyle(MonoCheckboxToggleStyle())
                    .help(alarmEnabled.wrappedValue ? "Disable alarm" : "Enable alarm")
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

    /// Two-way binding for the row's alarm switch, backed by the per-event setting in
    /// `SettingsStore` (which persists it and is what `AlarmManager` checks before firing).
    private var alarmEnabled: Binding<Bool> {
        Binding(
            get: { settingsStore.isAlarmEnabled(eventID: event.eventIdentifier) },
            set: { newValue in
                if newValue != settingsStore.isAlarmEnabled(eventID: event.eventIdentifier) {
                    settingsStore.toggleEventAlarm(eventID: event.eventIdentifier)
                }
            }
        )
    }

    /// True when this timed event's alarm is unchecked, so its text is shown faded.
    /// All-day events have no alarm control and are never dimmed.
    private var isDimmed: Bool {
        !event.isAllDay && !alarmEnabled.wrappedValue
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

/// Single-colour checkbox for the per-event alarm: an empty square when off and a filled square
/// with a knocked-out tick when on, both in the primary label colour (black in light mode,
/// white in dark mode). Used instead of the system checkbox, which always fills with the
/// accent colour when checked.
private struct MonoCheckboxToggleStyle: ToggleStyle {
    /// Draws the checkbox symbol as a borderless button that flips the toggle's value.
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                .font(.system(size: 16))
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel("Alarm")
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
