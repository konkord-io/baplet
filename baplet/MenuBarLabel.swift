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
/// lazily on first click), so it also owns app startup and re-fetches events whenever the
/// calendar selection or the number of days changes, wherever that change was made.
struct MenuBarLabel: View {
    @Environment(CalendarService.self) private var calendarService
    @Environment(SettingsStore.self) private var settingsStore
    @Environment(AlarmManager.self) private var alarmManager
    @Environment(\.openWindow) private var openWindow

    /// Set once the global Today shortcut has its handler, so a repeated `.task` run (when
    /// SwiftUI recreates the label) can't register a second one that toggles the panel twice.
    private static var registeredTodayShortcut = false

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
        .onChange(of: settingsStore.enabledCalendarIDs) {
            reloadEvents()
        }
        .onChange(of: settingsStore.daysToShow) {
            reloadEvents()
        }
    }

    /// Runs once at launch: registers the global Today shortcut, requests calendar access if
    /// needed, loads calendars and events, and starts the alarm timer so alarms fire without
    /// the menu ever being opened.
    /// When access is granted but no calendars are selected, it opens the welcome guide on a
    /// fresh install, or Settings if the guide was already finished.
    private func startUp() async {
        if !Self.registeredTodayShortcut {
            Self.registeredTodayShortcut = true
            KeyboardShortcuts.onKeyUp(for: .showToday) { [calendarService, settingsStore] in
                TodayPanel.toggle(calendarService: calendarService, settingsStore: settingsStore)
            }
        }

        if calendarService.authorizationStatus == .notDetermined {
            await calendarService.requestAccess()
        }
        guard calendarService.authorizationStatus == .fullAccess else { return }

        calendarService.loadCalendars()
        calendarService.fetchEvents(for: settingsStore)
        alarmManager.start(calendarService: calendarService, settingsStore: settingsStore)

        if settingsStore.enabledCalendarIDs.isEmpty {
            if settingsStore.onboardingCompleted {
                openWindow.openSettings()
            } else {
                openWindow.openWelcome()
            }
        }
    }

    /// Re-fetches the event list for the current selection and updates the menu bar status,
    /// so the menu and alarms follow a change in Settings or the welcome guide right away.
    private func reloadEvents() {
        calendarService.fetchEvents(for: settingsStore)
        alarmManager.recheckNow()
    }
}

/// Identifiers of Baplet's window scenes, shared by the scene definitions and the code that
/// opens or closes them.
enum WindowID {
    static let settings = "settings"
    static let welcome = "welcome"
}

extension OpenWindowAction {
    /// How long to wait after asking SwiftUI to open a window before bringing it forward,
    /// giving the window time to exist.
    private static let activationDelay: TimeInterval = 0.1

    /// Opens the Settings window and brings it to the front.
    func openSettings() {
        openInFront(id: WindowID.settings)
    }

    /// Opens the welcome guide window and brings it to the front.
    func openWelcome() {
        openInFront(id: WindowID.welcome)
    }

    /// Opens the window scene with the given id and brings it to the front.
    /// Baplet is an agent app (no Dock icon), so the app must be activated explicitly
    /// or the window would open behind whatever app currently has focus.
    private func openInFront(id: String) {
        callAsFunction(id: id)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.activationDelay) {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.identifier?.rawValue == id {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }
}
