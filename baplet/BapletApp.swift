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

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(calendarService)
                .environment(settingsStore)
                .environment(alarmManager)
        } label: {
            MenuBarLabel()
                .environment(calendarService)
                .environment(settingsStore)
                .environment(alarmManager)
        }
        .menuBarExtraStyle(.window)

        Window("Settings", id: "settings") {
            SettingsView()
                .environment(calendarService)
                .environment(settingsStore)
                .environment(alarmManager)
        }
        .defaultSize(width: 580, height: 420)
        .windowResizability(.contentMinSize)
    }
}
