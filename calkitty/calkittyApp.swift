//
//  alarminaApp.swift
//  alarmina
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import SwiftUI

@main
struct alarminaApp: App {
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
            Label {
                Text("Alarmina")
            } icon: {
                if let label = alarmManager.menuBarStatus.label {
                    HStack(spacing: 2) {
                        Image(systemName: alarmManager.menuBarStatus.icon)
                        Text(label)
                            .monospacedDigit()
                    }
                    .frame(minWidth: 40, alignment: .leading)
                } else {
                    Image(systemName: alarmManager.menuBarStatus.icon)
                        .frame(minWidth: 20)
                }
            }
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
