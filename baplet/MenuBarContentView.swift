//
//  MenuBarContentView.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import EventKit
import SwiftUI

/// Main popover content displayed when clicking the menu bar icon.
/// Shows upcoming events grouped by day, handles authorization states,
/// and provides access to settings and quit.
struct MenuBarContentView: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AlarmManager.self) private var alarmManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(width: 360)
        .task {
            await initialLoad()
        }
    }

    /// Checks authorization on launch and either loads data directly or requests access.
    private func initialLoad() async {
        switch calendarService.authorizationStatus {
        case .fullAccess:
            calendarService.loadCalendars()
            calendarService.fetchEvents(enabledCalendarIDs: settingsStore.enabledCalendarIDs, daysToShow: settingsStore.daysToShow)
            alarmManager.start(calendarService: calendarService, settingsStore: settingsStore)
        case .notDetermined:
            await calendarService.requestAccess()
            if calendarService.authorizationStatus == .fullAccess {
                calendarService.fetchEvents(enabledCalendarIDs: settingsStore.enabledCalendarIDs, daysToShow: settingsStore.daysToShow)
                alarmManager.start(calendarService: calendarService, settingsStore: settingsStore)
            }
        default:
            break
        }
    }

    @Environment(\.openWindow) private var openWindow

    /// Header bar displaying the app name with refresh, settings, and quit buttons.
    private var header: some View {
        HStack(spacing: 12) {
            Text("Baplet")
                .font(.headline)
            Spacer()
            Button {
                calendarService.refresh(enabledCalendarIDs: settingsStore.enabledCalendarIDs, daysToShow: settingsStore.daysToShow)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)

            Button {
                settingsStore.alarmsPaused.toggle()
                alarmManager.recheckNow()
            } label: {
                Image(systemName: settingsStore.alarmsPaused ? "bell.slash" : "bell")
            }
            .buttonStyle(.borderless)
            .help(settingsStore.alarmsPaused ? "Resume alarms" : "Pause alarms")

            Button {
                openWindow(id: "settings")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    NSApp.activate(ignoringOtherApps: true)
                    for window in NSApp.windows where window.identifier?.rawValue == "settings" || window.title == "Settings" {
                        window.makeKeyAndOrderFront(nil)
                    }
                }
            } label: {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    /// Main content area that adapts based on authorization status.
    @ViewBuilder
    private var content: some View {
        switch calendarService.authorizationStatus {
        case .fullAccess:
            eventList
        case .notDetermined:
            statusView(
                icon: "calendar",
                title: "Calendar Access",
                message: "Requesting calendar access..."
            )
        case .denied:
            statusView(
                icon: "calendar.badge.exclamationmark",
                title: "Access Denied",
                message: "Open System Settings \u{2192} Privacy & Security \u{2192} Calendars to grant access.",
                action: ("Open System Settings", openCalendarSettings)
            )
        case .restricted:
            statusView(
                icon: "lock.shield",
                title: "Restricted",
                message: "Calendar access is restricted by a system policy."
            )
        case .writeOnly:
            statusView(
                icon: "calendar.badge.minus",
                title: "Write-Only Access",
                message: "Baplet needs full calendar access. Open System Settings to update permissions.",
                action: ("Open System Settings", openCalendarSettings)
            )
        @unknown default:
            statusView(
                icon: "questionmark.circle",
                title: "Unknown Status",
                message: "Unexpected authorization status."
            )
        }
    }

    /// Scrollable list of events grouped by day with section headers.
    private var eventList: some View {
        Group {
            let dayGroups = calendarService.eventsByDay()
            if dayGroups.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "calendar")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text("No upcoming events")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, minHeight: 120)
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(dayGroups, id: \.day) { group in
                            Section {
                                ForEach(group.events, id: \.eventIdentifier) { event in
                                    CalendarEventRow(event: event)
                                }
                            } header: {
                                Text(dayLabel(for: group.day))
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)
                                    .padding(.horizontal, 12)
                                    .padding(.top, 8)
                                    .padding(.bottom, 4)
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)
            }
        }
    }

    /// Returns a human-readable label for a given day: "Today", "Tomorrow", or a formatted date.
    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInTomorrow(date) {
            return "Tomorrow"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            return formatter.string(from: date)
        }
    }

    /// Reusable status view for non-authorized states.
    private func statusView(
        icon: String,
        title: String,
        message: String,
        action: (String, @MainActor () -> Void)? = nil
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let action {
                Button(action.0, action: action.1)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .padding()
    }

    /// Opens the Calendar privacy section in System Settings.
    private func openCalendarSettings() {
        NSWorkspace.shared.open(
            URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!
        )
    }
}
