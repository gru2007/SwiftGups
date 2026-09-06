//
//  SwiftGupsApp.swift
//  SwiftGups
//
//  Created by Руслан Артемьев on 25.08.2025.
//

import SwiftUI
import SwiftData
import CloudKit
import UIKit
import DebugSwift

@main
struct SwiftGupsApp: App {
    @UIApplicationDelegateAdaptor(SwiftGupsAppDelegate.self) private var appDelegate
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
                // Shake-to-toggle DebugSwift (работает в DEBUG + TestFlight)
                .background(ShakeDetectorView().allowsHitTesting(false))
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

        // Имя хранилища одно и то же с зеркалированием и без него: иначе при
        // переключении режима данные пользователя «пропадают» — открылся бы
        // другой файл. CoreData спокойно открывает store с метаданными
        // CloudKit и без самого зеркалирования.
        let cloudKitDatabase: ModelConfiguration.CloudKitDatabase = AppEnvironment.isCloudKitAvailable
            ? .private("iCloud.tech.artemev.swiftgups")
            : .none

        let modelConfiguration = ModelConfiguration(
            "SwiftGupsModel",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: cloudKitDatabase
        )

        do {
            let container = try ModelContainer(for: schema, configurations: [modelConfiguration])
            if AppEnvironment.isCloudKitAvailable {
                print("✅ SwiftData container created with CloudKit sync enabled")
            } else {
                print("ℹ️ SwiftData container created without CloudKit (нет entitlements)")
            }
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

// MARK: - DebugSwift (DEBUG + TestFlight)

private enum DebugMenuEnvironment {
    static var isDebug: Bool {
#if DEBUG
        true
#else
        false
#endif
    }
    
    /// TestFlight installs use `sandboxReceipt`.
    static var isTestFlight: Bool {
        Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt"
    }
    
    static var isEnabled: Bool {
        // В LiveContainer меню нужно: его сетевой лог — самый быстрый способ
        // увидеть, что именно ответил сервер. Раньше оно было выключено из-за
        // обработчика крэшей DebugSwift, который сам падал в dladdr, разбирая
        // чужие образы, — но падал он, только пока приложение падало на
        // CloudKit. Эту причину убрали, а инструмент вернули.
        isDebug || isTestFlight || AppEnvironment.isLiveContainerBuild
    }
}

final class SwiftGupsAppDelegate: NSObject, UIApplicationDelegate {
    static var shared: SwiftGupsAppDelegate?
    
    let debugSwift = DebugSwift()
    
    override init() {
        super.init()
        Self.shared = self
    }
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        guard DebugMenuEnvironment.isEnabled else { return true }
        
        // Setup early; show when app becomes active (window is ready).
        debugSwift.setup()
        return true
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        // Чтобы не "светить" дебаг-меню в TestFlight (включая возможный Apple beta review),
        // показываем его автоматически только в DEBUG. В TestFlight — открывается по shake.
        guard DebugMenuEnvironment.isDebug else { return }
        debugSwift.show()
    }
    
    func toggleDebugMenu() {
        guard DebugMenuEnvironment.isEnabled else { return }
        debugSwift.toggle()
    }
}

// MARK: - Shake detector (SwiftUI-friendly)

private struct ShakeDetectorView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ShakeDetectorViewController {
        ShakeDetectorViewController()
    }
    
    func updateUIViewController(_ uiViewController: ShakeDetectorViewController, context: Context) {}
}

private final class ShakeDetectorViewController: UIViewController {
    override var canBecomeFirstResponder: Bool { true }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        becomeFirstResponder()
    }
    
    override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        super.motionEnded(motion, with: event)
        
        guard motion == .motionShake, DebugMenuEnvironment.isEnabled else { return }
        SwiftGupsAppDelegate.shared?.toggleDebugMenu()
    }
    
    override func loadView() {
        // Invisible, non-interactive view that still participates in responder chain.
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        self.view = view
    }
}
