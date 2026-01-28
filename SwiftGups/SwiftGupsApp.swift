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
    @StateObject private var liveActivityManager = LiveActivityManager()
    @Environment(\.scenePhase) private var scenePhase
    
    // Кешируем ModelContainer, чтобы не создавать его несколько раз
    private static var cachedModelContainer: ModelContainer?
    
    init() {
        // Регистрируем фоновые задачи при запуске приложения
        if #available(iOS 13.0, *) {
            BackgroundTaskManager.shared.registerBackgroundTasks()
        }
    }
    
    var body: some Scene {
        WindowGroup {
            MainAppView()
                .environmentObject(liveActivityManager)
        }
        .modelContainer(Self.getOrCreateModelContainer())
        .onChange(of: scenePhase) { oldPhase, newPhase in
            if #available(iOS 13.0, *) {
                handleScenePhaseChange(from: oldPhase, to: newPhase)
            }
        }
    }
    
    private static func getOrCreateModelContainer() -> ModelContainer {
        if let cached = cachedModelContainer {
            return cached
        }
        let container = createModelContainer()
        cachedModelContainer = container
        return container
    }
    
    private static func createModelContainer() -> ModelContainer {
        let schema = Schema([User.self, Homework.self])
        
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
    
    @available(iOS 13.0, *)
    private func handleScenePhaseChange(from oldPhase: ScenePhase, to newPhase: ScenePhase) {
        switch newPhase {
        case .background:
            // Приложение уходит в фон - планируем фоновые задачи только если они еще не запланированы
            if liveActivityManager.isEnabled {
                BackgroundTaskManager.shared.scheduleBackgroundRefresh()
                print("📱 App went to background")
            }
        case .active:
            // При переходе в активное состояние не планируем задачи повторно
            // Они уже должны быть запланированы при включении Live Activity
            break
        case .inactive:
            // Приложение неактивно (переходное состояние)
            break
        @unknown default:
            break
        }
    }
    

}
