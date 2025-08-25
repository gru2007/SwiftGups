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
        let schema = Schema([User.self, Homework.self])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false, cloudKitDatabase: .automatic)
        
        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            
            // Проверяем доступность iCloud в фоне
            Task {
                await checkCloudKitAvailability()
            }
            
            return container
        } catch {
            print("Failed to create CloudKit container: \(error)")
            
            // Fallback: создаем локальный контейнер без CloudKit
            let localConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            
            do {
                let localContainer = try ModelContainer(for: schema, configurations: [localConfiguration])
                print("Using local storage only (CloudKit unavailable)")
                return localContainer
            } catch {
                fatalError("Failed to create local container: \(error)")
            }
        }
    }
    
    @MainActor
    private func checkCloudKitAvailability() async {
        let container = CKContainer.default()
        
        do {
            let accountStatus = try await container.accountStatus()
            
            switch accountStatus {
            case .available:
                print("iCloud account available - CloudKit sync enabled")
            case .noAccount:
                print("No iCloud account - using local storage only")
            case .restricted:
                print("iCloud account restricted - using local storage only")
            case .couldNotDetermine:
                print("Could not determine iCloud status - using local storage only")
            case .temporarilyUnavailable:
                print("iCloud temporarily unavailable - using local storage only")
            @unknown default:
                print("Unknown iCloud status - using local storage only")
            }
        } catch {
            print("Error checking iCloud availability: \(error)")
        }
    }
}