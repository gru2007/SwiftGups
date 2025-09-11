//
//  SwiftGupsApp.swift
//  SwiftGups
//
//  Created by Руслан Артемьев on 25.08.2025.
//

import SwiftUI
import SwiftData
import CloudKit

@main
struct SwiftGupsApp: App {
    var body: some Scene {
        WindowGroup {
            MainAppView()
        }
        .modelContainer(createModelContainer())
    }
    
    private func createModelContainer() -> ModelContainer {
        let schema = Schema([User.self, Homework.self, HomeworkAttachment.self])
        
        let modelConfiguration = ModelConfiguration(
            "SwiftGupsModel",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private("iCloud.tech.artemev.swiftgups")
        )
        
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            print("✅ SwiftData container created with CloudKit sync enabled")
            return container
        } catch {
            print("❌ Failed to create CloudKit container: \(error)")
            
            // Fallback: создаем локальный контейнер без CloudKit
            let localConfiguration = ModelConfiguration(
                "SwiftGupsModelLocal",
                schema: schema,
                isStoredInMemoryOnly: false
            )
            
            do {
                let localContainer = try ModelContainer(for: schema, configurations: [localConfiguration])
                print("⚠️ Using local storage only (CloudKit unavailable)")
                return localContainer
            } catch {
                fatalError("💥 Failed to create local container: \(error)")
            }
        }
    }
    

}
