//
//  SwiftGupsApp.swift
//  SwiftGups
//
//  Created by Руслан Артемьев on 25.08.2025.
//

import SwiftUI
import SwiftData

@main
struct SwiftGupsApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            User.self,
            Homework.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isCloudKitEnabled: true)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            MainAppView()
        }
        .modelContainer(sharedModelContainer)
    }
}
