//
//  SettingsView.swift
//  calkitty
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import EventKit
import SwiftUI

/// Settings window using a macOS System Settings-style sidebar navigation.
struct SettingsView: View {
    private enum SettingsPane: String, Hashable, CaseIterable {
        case calendars
        case alerts

        /// Display label for the sidebar row.
        var label: String {
            switch self {
            case .calendars: "Calendars"
            case .alerts: "Alerts"
            }
        }

        /// SF Symbol name for the sidebar row icon.
        var icon: String {
            switch self {
            case .calendars: "calendar"
            case .alerts: "bell"
            }
        }
    }

    @State private var selectedPane: SettingsPane = .calendars

    var body: some View {
        NavigationSplitView {
            List(SettingsPane.allCases, id: \.self, selection: $selectedPane) { pane in
                Label(pane.label, systemImage: pane.icon)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            switch selectedPane {
            case .calendars:
                CalendarsPane()
            case .alerts:
                AlertsPane()
            }
        }
        .frame(minWidth: 500, idealWidth: 580, minHeight: 350, idealHeight: 420)
    }
}

/// Pane for selecting which calendars to include in the event list and alarm system.
private struct CalendarsPane: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        Group {
        if calendarService.sources.isEmpty {
            ContentUnavailableView {
                Label("No Calendars", systemImage: "calendar")
            } description: {
                Text("No calendar sources found. Grant calendar access first.")
            }
        } else {
            Form {
                ForEach(calendarService.sources, id: \.sourceIdentifier) { source in
                    let sourceCalendars = calendarService.calendars(for: source)
                    if !sourceCalendars.isEmpty {
                        Section(source.title) {
                            ForEach(sourceCalendars, id: \.calendarIdentifier) { calendar in
                                Toggle(isOn: Binding(
                                    get: { settingsStore.isCalendarEnabled(calendarID: calendar.calendarIdentifier) },
                                    set: { _ in
                                        settingsStore.toggleCalendar(calendarID: calendar.calendarIdentifier)
                                        calendarService.fetchEvents(enabledCalendarIDs: settingsStore.enabledCalendarIDs, daysToShow: settingsStore.daysToShow)
                                    }
                                )) {
                                    HStack(spacing: 8) {
                                        Circle()
                                            .fill(Color(cgColor: calendar.cgColor))
                                            .frame(width: 10, height: 10)
                                        Text(calendar.title)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    HStack {
                        Spacer()
                        Button("Select All") { selectAll() }
                        Button("Deselect All") { deselectAll() }
                    }
                }
            }
            .formStyle(.grouped)
        }
        }
        .navigationTitle("Calendars")
    }

    /// Enables all calendars and refreshes the event list.
    private func selectAll() {
        let allIDs = calendarService.calendars.map(\.calendarIdentifier)
        settingsStore.enabledCalendarIDs = Set(allIDs)
        calendarService.fetchEvents(enabledCalendarIDs: settingsStore.enabledCalendarIDs, daysToShow: settingsStore.daysToShow)
    }

    /// Disables all calendars and refreshes the event list.
    private func deselectAll() {
        settingsStore.enabledCalendarIDs = []
        calendarService.fetchEvents(enabledCalendarIDs: settingsStore.enabledCalendarIDs, daysToShow: settingsStore.daysToShow)
    }
}

/// Pane for configuring alert style and timing.
private struct AlertsPane: View {
    @Environment(SettingsStore.self) private var settingsStore

    var body: some View {
        @Bindable var settings = settingsStore

        Form {
            Section("Alert Style") {
                Picker("Style", selection: $settings.alertStyle) {
                    ForEach(AlertStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
            }

            Section("Sound") {
                Toggle("Play sound on alert", isOn: $settings.soundEnabled)
            }

            Section("Timing") {
                Stepper(
                    "Alert \(settingsStore.minutesBefore) minutes before event",
                    value: $settings.minutesBefore,
                    in: 1...60
                )
            }

            Section("Display") {
                Stepper(
                    "Show \(settingsStore.daysToShow) \(settingsStore.daysToShow == 1 ? "day" : "days") of events",
                    value: $settings.daysToShow,
                    in: 1...14
                )
            }

            Section("Preview") {
                LabeledContent("Test the selected alert style") {
                    Button("Test Alert") {
                        testAlert()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Alerts")
    }

    /// Fires a test alert of the currently selected style to preview its appearance.
    private func testAlert() {
        let mockMeetingLink = AlertService.MeetingLink(
            serviceName: "Google Meet",
            icon: "video",
            url: URL(string: "https://meet.google.com/abc-defg-hij")!
        )

        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        let now = Date()
        let mockEnd = now.addingTimeInterval(30 * 60)
        let timeString = "Now \(formatter.string(from: now)) \u{00b7} \(formatter.string(from: now)) \u{2013} \(formatter.string(from: mockEnd))"

        if settingsStore.soundEnabled {
            AlertService.playAlarmSound()
        }

        let style = settingsStore.alertStyle

        switch style {
        case .popupDialog:
            AlertService.showPopupAlert(
                title: "Test Event",
                time: timeString,
                location: "Conference Room A",
                calendarName: "Work",
                meetingLink: mockMeetingLink,
                onDismiss: {},
                onSnooze: { _ in },
                onOpenInCalendar: {}
            )

        case .fullScreenGlassmorphic, .fullScreenBoldMinimal, .fullScreenWarmPlayful:
            AlertService.showFullScreenAlert(
                style: style,
                title: "Test Event",
                time: timeString,
                location: "Conference Room A",
                calendarName: "Work",
                meetingLink: mockMeetingLink,
                onDismiss: {},
                onSnooze: { _ in },
                onOpenInCalendar: {}
            )
        }
    }
}
