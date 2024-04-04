//
//  FlySightApp.swift
//  FlySight
//
//  Created by Michael Cooper on 2024-04-04.
//

import SwiftUI

@main
struct FlySightApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
