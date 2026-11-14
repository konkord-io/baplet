//
//  MenuBarLabel.swift
//  baplet
//

import AppKit
import EventKit
import KeyboardShortcuts
import SwiftUI

/// The always-visible menu bar item: the Baplet "b" template icon (faded while alarms are
/// paused) plus an optional countdown.
/// SwiftUI renders it as soon as the app launches (unlike the menu window, which is built
/// lazily on first click), so it also owns app startup.
struct MenuBarLabel: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AlarmManager.self) private var alarmManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label {
            Text("Baplet")
        } icon: {
            HStack(spacing: 2) {
                Image("BapletToolbar")
                    .opacity(alarmManager.menuBarStatus.isDimmed ? 0.4 : 1)
                if let label = alarmManager.menuBarStatus.label {
                    Text(label)
                        .monospacedDigit()
                }
            }
        }
        .task {
            await startUp()
        }
    }

    /// Runs once at launch: registers the global Today shortcut, requests calendar access if
    /// needed, loads calendars and events, and starts the alarm timer so alarms fire without
    /// the menu ever being opened.
    /// When access is granted but no calendars are selected, it opens the welcome guide on a
    /// fresh install, or Settings if the guide was already finished.
    private func startUp() async {
        KeyboardShortcuts.onKeyUp(for: .showToday) { [calendarService, settingsStore] in
            TodayPanel.toggle(calendarService: calendarService, settingsStore: settingsStore)
        }

        if calendarService.authorizationStatus == .notDetermined {
            await calendarService.requestAccess()
        }
        guard calendarService.authorizationStatus == .fullAccess else { return }

        calendarService.loadCalendars()
        calendarService.fetchEvents(enabledCalendarIDs: settingsStore.enabledCalendarIDs, daysToShow: settingsStore.daysToShow)
        alarmManager.start(calendarService: calendarService, settingsStore: settingsStore)

        if settingsStore.enabledCalendarIDs.isEmpty {
            if settingsStore.onboardingCompleted {
                openWindow.openSettings()
            } else {
                openWindow.openWelcome()
            }
        }
    }
}

extension OpenWindowAction {
    /// Opens the Settings window and brings it to the front.
    @MainActor
    func openSettings() {
        openInFront(id: "settings")
    }

    /// Opens the welcome guide window and brings it to the front.
    @MainActor
    func openWelcome() {
        openInFront(id: "welcome")
    }

    /// Opens the window scene with the given id and brings it to the front.
    /// Baplet is an agent app (no Dock icon), so the app must be activated explicitly
    /// or the window would open behind whatever app currently has focus.
    @MainActor
    private func openInFront(id: String) {
        callAsFunction(id: id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.identifier?.rawValue == id {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
