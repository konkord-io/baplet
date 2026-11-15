//
//  MenuBarContentView.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import AppKit
import EventKit
import SwiftUI

/// Main window content displayed when clicking the menu bar icon.
/// Shows upcoming events grouped by day, handles authorization states,
/// and provides access to settings and quit.
struct MenuBarContentView: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AlarmManager.self) private var alarmManager
    @Environment(UpdateService.self) private var updateService
    @Environment(\.openWindow) private var openWindow

    /// Bumped on every refresh click; the refresh icon spins one turn each time it changes,
    /// giving visible feedback for a reload that otherwise completes instantly.
    @State private var refreshCount = 0

    /// Keyboard selection in the event list; empty until the first arrow key or pointer move.
    @State private var selection = EventListSelection()

    /// Watches keys typed into the menu window: ↑/↓, Return / ⌘Return and D, as in Today.
    @State private var keyMonitor = PanelKeyMonitor()

    /// The menu's window, found by `WindowReader`; its losing key status means the menu closed.
    @State private var menuWindow: NSWindow?

    var body: some View {
        VStack(spacing: 0) {
            header
                .zIndex(1)
            Divider()
            content
            if let update = updateService.availableUpdate {
                Divider()
                updateRow(version: update.version.description)
            }
        }
        .frame(width: 420)
        .background(WindowReader { installKeyHandling(for: $0) })
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { note in
            if let menuWindow, note.object as? NSWindow === menuWindow {
                selection.reset()
            }
        }
    }

    /// Handles the menu's keys like the Today panel's: ↑/↓ select an event, Return does the
    /// Settings → Shortcuts action and ⌘Return the other one, D switches the selected event's
    /// alarm, and Escape closes the menu. Return and D pass through while nothing is selected. The handler only reads
    /// reference types, so it sees fresh events and settings although it is installed once.
    private func installKeyHandling(for window: NSWindow) {
        guard menuWindow !== window else { return }
        menuWindow = window
        let calendarService = calendarService
        let settingsStore = settingsStore
        let selection = selection
        keyMonitor.start(for: window) { [weak window] event in
            let events = calendarService.eventsByDay().flatMap(\.events)
            let keys = events.compactMap(\.alarmKey)
            let selected = selection.selectedKey.flatMap { key in events.first { $0.alarmKey == key } }
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])

            switch event.keyCode {
            case KeyCode.downArrow:
                selection.move(by: 1, in: keys)
                return nil
            case KeyCode.upArrow:
                selection.move(by: -1, in: keys)
                return nil
            case KeyCode.escape where modifiers.isEmpty:
                window?.close()
                return nil
            case KeyCode.returnKey, KeyCode.keypadEnter:
                guard let selected else { return event }
                let action = modifiers == .command
                    ? settingsStore.todayReturnAction.alternate
                    : settingsStore.todayReturnAction
                action.perform(on: selected, settingsStore: settingsStore)
                return nil
            default:
                break
            }

            if modifiers.isEmpty, event.charactersIgnoringModifiers?.lowercased() == "d",
               let selected, !selected.isAllDay, let key = selected.alarmKey {
                settingsStore.toggleEventAlarm(key: key)
                return nil
            }
            return event
        }
    }

    /// Row at the bottom of the menu announcing a newer release; opens the update dialog.
    private func updateRow(version: String) -> some View {
        Button {
            openWindow.openUpdate()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(.tint)
                Text("Update available: \(version)")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    /// Header bar with the app name and the refresh, Today, pause/resume, settings and quit
    /// buttons.
    private var header: some View {
        HStack(spacing: 4) {
            Text("Baplet")
                .font(.headline)
            Spacer()
            Button {
                refreshCount += 1
                calendarService.refresh(for: settingsStore)
            } label: {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, value: refreshCount)
            }
            .buttonStyle(.headerIcon(help: "Refresh events"))

            Button {
                TodayPanel.show(calendarService: calendarService, settingsStore: settingsStore)
            } label: {
                Image(systemName: "calendar.day.timeline.left")
            }
            .buttonStyle(.headerIcon(help: "Show today's events"))

            Button {
                settingsStore.alarmsPaused.toggle()
                alarmManager.recheckNow()
            } label: {
                Image(systemName: settingsStore.alarmsPaused ? "bell.slash" : "bell")
                    .foregroundStyle(settingsStore.alarmsPaused ? AnyShapeStyle(Color("PausedRed")) : AnyShapeStyle(.primary))
            }
            .buttonStyle(.headerIcon(help: settingsStore.alarmsPaused ? "Resume alarms" : "Pause alarms"))

            Button {
                openWindow.openSettings()
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.headerIcon(help: "Settings"))

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.headerIcon(help: "Quit Baplet"))
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
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(dayGroups, id: \.day) { group in
                                Section {
                                    ForEach(group.events, id: \.alarmKey) { event in
                                        CalendarEventRow(
                                            event: event,
                                            isSelected: event.alarmKey != nil && selection.selectedKey == event.alarmKey,
                                            onHoverChange: { hovering in
                                                if hovering, let key = event.alarmKey {
                                                    selection.pointerEntered(key: key)
                                                }
                                            }
                                        )
                                        .id(event.alarmKey)
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
                        .padding(.bottom, 6)
                    }
                    .frame(maxHeight: 400)
                    .onChange(of: selection.selectedKey) { _, key in
                        if let key {
                            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(key) }
                        }
                    }
                }
            }
        }
    }

    /// Returns a human-readable label for a given day: "Today", "Tomorrow", or a formatted date.
    private func dayLabel(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: AppClock.now()) {
            return "Today"
        } else if calendar.date(byAdding: .day, value: 1, to: AppClock.now()).map { calendar.isDate(date, inSameDayAs: $0) } == true {
            return "Tomorrow"
        } else {
            return date.formatted(date: .abbreviated, time: .omitted)
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
