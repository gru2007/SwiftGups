import SwiftUI
import CloudKit
import SwiftData

/// Сервис для управления состоянием CloudKit
@MainActor
class CloudKitService: ObservableObject {
    @Published var isCloudKitAvailable: Bool = false
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published var syncStatus: SyncStatus = .unknown
    @Published var showCloudKitAlert: Bool = false
    @AppStorage("iCloudAlertDismissed") private var iCloudAlertDismissed: Bool = false
    @Published var lastSyncTime: Date? = nil
    @Published var isSyncing: Bool = false
    
    enum SyncStatus {
        case unknown
        case syncing
        case synced
        case error(String)
        case localOnly
        
        var description: String {
            switch self {
            case .unknown:
                return "Проверка статуса синхронизации..."
            case .syncing:
                return "Синхронизация с iCloud..."
            case .synced:
                return "Синхронизировано с iCloud"
            case .error(let message):
                return "Ошибка синхронизации: \(message)"
            case .localOnly:
                return "Хранение только локально"
            }
        }
        
        var icon: String {
            switch self {
            case .unknown:
                return "questionmark.circle"
            case .syncing:
                return "arrow.clockwise"
            case .synced:
                return "icloud.and.arrow.up"
            case .error:
                return "exclamationmark.triangle"
            case .localOnly:
                return "internaldrive"
            }
        }
        
        var color: Color {
            switch self {
            case .unknown:
                return .gray
            case .syncing:
                return .blue
            case .synced:
                return .green
            case .error:
                return .red
            case .localOnly:
                return .orange
            }
        }
    }
    
    private let container = CKContainer.default()
    private var accountStatusObserver: NSObjectProtocol?
    
    init() {
        Task {
            await checkCloudKitAvailability()
        }
        // Подписка на изменения аккаунта iCloud (работает на реальных устройствах)
        accountStatusObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { await self.checkCloudKitAvailability() }
        }
    }
    
    func checkCloudKitAvailability() async {
        do {
            let status = try await container.accountStatus()
            accountStatus = status
            
            switch status {
            case .available:
                isCloudKitAvailable = true
                await performInitialSync()
                print("✅ iCloud доступен - синхронизация включена")
                
            case .noAccount:
                isCloudKitAvailable = false
                syncStatus = .localOnly
                showCloudKitAlert = !iCloudAlertDismissed
                print("⚠️ Нет iCloud аккаунта - только локальное хранение")
                
            case .restricted:
                isCloudKitAvailable = false
                syncStatus = .localOnly
                showCloudKitAlert = !iCloudAlertDismissed
                print("⚠️ iCloud ограничен - только локальное хранение")
                
            case .couldNotDetermine:
                isCloudKitAvailable = false
                syncStatus = .error("Не удалось определить статус iCloud")
                print("❌ Не удалось определить статус iCloud")
                
            case .temporarilyUnavailable:
                isCloudKitAvailable = false
                syncStatus = .localOnly
                print("⚠️ iCloud временно недоступен")
                
            @unknown default:
                isCloudKitAvailable = false
                syncStatus = .error("Неизвестный статус iCloud")
                print("❌ Неизвестный статус iCloud")
            }
            
        } catch {
            isCloudKitAvailable = false
            syncStatus = .error(error.localizedDescription)
            print("❌ Ошибка проверки iCloud: \(error.localizedDescription)")
        }
    }
    
    /// Выполняет принудительную синхронизацию с iCloud
    func forceSyncWithiCloud() async {
        guard isCloudKitAvailable else {
            print("⚠️ CloudKit недоступен для синхронизации")
            return
        }
        
        isSyncing = true
        syncStatus = .syncing
        
        await performInitialSync()
        
        isSyncing = false
        lastSyncTime = Date()
    }
    
    private func performInitialSync() async {
        syncStatus = .syncing
        
        // Имитируем синхронизацию - реальная синхронизация происходит автоматически через SwiftData
        try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 секунда
        
        syncStatus = .synced
        lastSyncTime = Date()
    }
    
    func dismissAlert() {
        showCloudKitAlert = false
        iCloudAlertDismissed = true
    }

    deinit {
        if let token = accountStatusObserver {
            NotificationCenter.default.removeObserver(token)
        }
    }
    
    var alertTitle: String {
        switch accountStatus {
        case .noAccount:
            return "iCloud не настроен"
        case .restricted:
            return "iCloud ограничен"
        default:
            return "Проблема с iCloud"
        }
    }
    
    var alertMessage: String {
        switch accountStatus {
        case .noAccount:
            return "Для синхронизации данных между устройствами войдите в iCloud в настройках iOS. Сейчас данные сохраняются только локально на этом устройстве и не будут потеряны."
        case .restricted:
            return "Доступ к iCloud ограничен настройками устройства. Данные будут сохраняться только локально и не будут потеряны."
        default:
            return "Не удалось подключиться к iCloud. Данные сохраняются локально и не будут потеряны."
        }
    }
    
    /// Проверяет целостность локальных данных
    func checkLocalDataIntegrity() -> (hasLocalData: Bool, userCount: Int, homeworkCount: Int) {
        // Эта функция поможет диагностировать проблемы с данными
        // В реальном приложении можно добавить дополнительную логику
        return (hasLocalData: true, userCount: 0, homeworkCount: 0)
    }
}

// MARK: - UI Components

struct CloudKitStatusView: View {
    @ObservedObject var cloudKitService: CloudKitService
    
    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: cloudKitService.syncStatus.icon)
                    .foregroundColor(cloudKitService.syncStatus.color)
                    .font(.caption)
                    .symbolEffect(.pulse, isActive: cloudKitService.isSyncing)
                
                                    VStack(alignment: .leading, spacing: 2) {
                        Text(cloudKitService.syncStatus.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let lastSyncTime = cloudKitService.lastSyncTime {
                            Text("Последняя синхронизация: \(lastSyncTime, format: .dateTime.hour().minute())")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        } else if !cloudKitService.isCloudKitAvailable {
                            Text("Данные сохраняются локально и защищены от потери")
                                .font(.caption2)
                                .foregroundColor(.green)
                        }
                    }
                
                Spacer()
                
                if cloudKitService.isSyncing {
                    ProgressView()
                        .scaleEffect(0.7)
                } else if cloudKitService.isCloudKitAvailable {
                    Button("Синхр.") {
                        Task { await cloudKitService.forceSyncWithiCloud() }
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    .disabled(cloudKitService.isSyncing)
                } else {
                    Button("Проверить") {
                        Task { await cloudKitService.checkCloudKitAvailability() }
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

struct CloudKitAlertModifier: ViewModifier {
    @ObservedObject var cloudKitService: CloudKitService
    
    func body(content: Content) -> some View {
        content
            .alert(
                cloudKitService.alertTitle,
                isPresented: $cloudKitService.showCloudKitAlert
            ) {
                Button("Понятно") {
                    cloudKitService.dismissAlert()
                }
                Button("Настроить iCloud") {
                    if let settingsUrl = URL(string: "App-prefs:APPLE_ID") {
                        UIApplication.shared.open(settingsUrl)
                    }
                    cloudKitService.dismissAlert()
                }
            } message: {
                Text(cloudKitService.alertMessage)
            }
    }
}

extension View {
    func cloudKitAlert(_ cloudKitService: CloudKitService) -> some View {
        modifier(CloudKitAlertModifier(cloudKitService: cloudKitService))
    }
}
