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
/// Timed events get a checkbox that switches the alarm of this one occurrence on or off.
/// Declined and cancelled meetings show their title struck through.
struct CalendarEventRow: View {
    let event: EKEvent

    /// Called after the user joins the meeting or opens the event in Calendar from this row,
    /// so a container such as the Today panel can close itself.
    var onOpened: (() -> Void)? = nil

    /// Whether this row is the keyboard selection (menu and Today panel); drawn with an accent
    /// highlight.
    var isSelected = false

    /// Called when the pointer enters or leaves the row, so the menu and the Today panel can
    /// move their selection to the row under the mouse.
    var onHoverChange: ((Bool) -> Void)? = nil

    /// Opacity of rows that are faded: events with their alarm switched off here.
    static let fadedOpacity = 0.45

    @Environment(SettingsStore.self) private var settingsStore
    @State private var isHovered = false

    /// Lays out the row and handles hover and clicks. The pointing-hand cursor is set on every
    /// pointer move rather than with `.pointerStyle`, because AppKit cursor rects in the
    /// `MenuBarExtra` window stay inactive until the first click, leaving the cursor of the
    /// app underneath.
    var body: some View {
        HStack(spacing: 10) {
            CalendarColorDot(calendar: event.calendar)

            VStack(alignment: .leading, spacing: 2) {
                Text(event.displayTitle)
                    .font(.headline)
                    .strikethrough(event.attendance.isStruckThrough)

                Text(event.isAllDay ? "All Day" : event.timeRangeText)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let location = event.location, !location.isEmpty {
                    Text(location)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            .opacity(isDimmed ? Self.fadedOpacity : 1)
            .animation(.easeOut(duration: 0.15), value: isDimmed)

            Spacer()

            if let meetingLink = AlertService.extractMeetingLink(from: event) {
                Button {
                    BrowserService.openMeeting(meetingLink.url, settings: settingsStore)
                    onOpened?()
                } label: {
                    Image(systemName: meetingLink.icon)
                        .font(.system(size: 16))
                        .foregroundStyle(.blue)
                }
                .buttonStyle(.rowIcon)
                .hoverLabel("Join \(meetingLink.serviceName)")
            }

            if let alarmEnabled {
                Toggle("Alarm", isOn: alarmEnabled)
                    .toggleStyle(MonoCheckboxToggleStyle())
                    .hoverLabel(alarmEnabled.wrappedValue ? "Disable alarm" : "Enable alarm")
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(rowBackground)
        .zIndex(isHovered ? 1 : 0)
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active = phase { NSCursor.pointingHand.set() }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            onHoverChange?(hovering)
        }
        .onTapGesture {
            AlertService.openEventInCalendar(event)
            onOpened?()
        }
    }

    /// Accent highlight for the selected row, so the menu and the Today panel look the same.
    /// A row whose container tracks hover itself (`onHoverChange`, the Today panel) is
    /// highlighted only through `isSelected`, so the pointer and the keyboard never light up
    /// two rows; other rows (the menu) highlight themselves under the pointer.
    private var rowBackground: Color {
        let highlighted = isSelected || (isHovered && onHoverChange == nil)
        return highlighted ? Color.accentColor.opacity(0.25) : .clear
    }

    /// Two-way binding for the row's alarm checkbox, backed by this occurrence's setting in
    /// `SettingsStore` (which persists it and is what `AlarmManager` checks before firing).
    /// Nil for all-day events and events without an alarm key, which get no checkbox.
    private var alarmEnabled: Binding<Bool>? {
        guard !event.isAllDay, event.alarmKey != nil else { return nil }
        return Binding(
            get: { settingsStore.isAlarmEnabled(for: event) },
            set: { newValue in
                if newValue != settingsStore.isAlarmEnabled(for: event) {
                    settingsStore.toggleEventAlarm(for: event)
                }
            }
        )
    }

    /// True when this event's alarm checkbox is unchecked, so its text is shown faded.
    /// Rows without a checkbox are never dimmed.
    private var isDimmed: Bool {
        alarmEnabled.map { !$0.wrappedValue } ?? false
    }
}

/// The small filled circle in a calendar's colour, shown next to calendars and events.
struct CalendarColorDot: View {
    let calendar: EKCalendar?
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(calendar.map { Color(cgColor: $0.cgColor) } ?? Color.secondary)
            .frame(width: size, height: size)
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
        }
        .buttonStyle(.rowIcon)
        .accessibilityLabel("Alarm")
        .accessibilityValue(configuration.isOn ? "On" : "Off")
    }
}
