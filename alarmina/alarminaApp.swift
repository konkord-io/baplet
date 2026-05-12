//
//  alarminaApp.swift
//  alarmina
//
//  Created by Jakob Vad Nielsen on 12/05/2026.
//

import SwiftUI
import CoreData

@main
struct alarminaApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
