//
//  BapletApp.swift
//  baplet
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import SwiftUI

@main
struct BapletApp: App {
    @State private var calendarService = CalendarService()
    @State private var settingsStore = SettingsStore()
    @State private var alarmManager = AlarmManager()
    @State private var updateService = UpdateService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(calendarService)
                .environment(settingsStore)
                .environment(alarmManager)
                .environment(updateService)
        } label: {
            MenuBarLabel()
                .environment(calendarService)
                .environment(settingsStore)
                .environment(alarmManager)
                .environment(updateService)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: WindowID.settings) {
            SettingsView()
                .environment(calendarService)
                .environment(settingsStore)
                .environment(alarmManager)
                .environment(updateService)
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)

        Window("Welcome to Baplet", id: WindowID.welcome) {
            OnboardingView()
                .environment(calendarService)
                .environment(settingsStore)
                .environment(alarmManager)
                .environment(updateService)
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .defaultLaunchBehavior(.suppressed)

        Window("Software Update", id: WindowID.update) {
            UpdateDialogView()
                .environment(updateService)
        }
        .windowResizability(.contentSize)
        .windowLevel(.floating)
        .defaultLaunchBehavior(.suppressed)
    }
}
