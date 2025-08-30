import SwiftUI
import CloudKit

/// Упрощенный сервис для отображения статуса CloudKit
/// SwiftData автоматически управляет синхронизацией
@MainActor
class CloudKitService: ObservableObject {
    @Published var accountStatus: CKAccountStatus = .couldNotDetermine
    @Published var showCloudKitAlert: Bool = false
    @AppStorage("iCloudAlertDismissed") private var iCloudAlertDismissed: Bool = false
    
    var isCloudKitAvailable: Bool {
        return accountStatus == .available
    }
    
    var statusDescription: String {
        switch accountStatus {
        case .available:
            return "Синхронизация с iCloud активна"
        case .noAccount:
            return "Войдите в iCloud для синхронизации"
        case .restricted:
            return "iCloud ограничен настройками"
        case .couldNotDetermine:
            return "Проверка статуса iCloud..."
        case .temporarilyUnavailable:
            return "iCloud временно недоступен"
        @unknown default:
            return "Неизвестный статус iCloud"
        }
    }
    
    var statusIcon: String {
        switch accountStatus {
        case .available:
            return "icloud.and.arrow.up"
        case .noAccount, .restricted:
            return "icloud.slash"
        case .couldNotDetermine:
            return "questionmark.circle"
        case .temporarilyUnavailable:
            return "icloud.and.arrow.down"
        @unknown default:
            return "exclamationmark.triangle"
        }
    }
    
    var statusColor: Color {
        switch accountStatus {
        case .available:
            return .green
        case .noAccount, .restricted:
            return .orange
        case .couldNotDetermine:
            return .gray
        case .temporarilyUnavailable:
            return .yellow
        @unknown default:
            return .red
        }
    }
    
    private let container = CKContainer.default()
    private var accountStatusObserver: NSObjectProtocol?
    
    init() {
        Task {
            await checkAccountStatus()
        }
        // Подписка на изменения аккаунта iCloud
        accountStatusObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name.CKAccountChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            Task { await self.checkAccountStatus() }
        }
    }
    
    func checkAccountStatus() async {
        do {
            let status = try await container.accountStatus()
            accountStatus = status
            
            switch status {
            case .available:
                print("✅ iCloud доступен - SwiftData автоматически синхронизирует данные")
                
            case .noAccount:
                showCloudKitAlert = !iCloudAlertDismissed
                print("⚠️ Нет iCloud аккаунта - данные сохраняются локально")
                
            case .restricted:
                showCloudKitAlert = !iCloudAlertDismissed
                print("⚠️ iCloud ограничен - данные сохраняются локально")
                
            case .couldNotDetermine:
                print("❌ Не удалось определить статус iCloud")
                
            case .temporarilyUnavailable:
                print("⚠️ iCloud временно недоступен")
                
            @unknown default:
                print("❌ Неизвестный статус iCloud")
            }
            
        } catch {
            print("❌ Ошибка проверки iCloud: \(error.localizedDescription)")
        }
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
            return "Для синхронизации данных между устройствами войдите в iCloud в настройках iOS. Данные сохраняются локально и автоматически синхронизируются при подключении к iCloud."
        case .restricted:
            return "Доступ к iCloud ограничен настройками устройства. Данные сохраняются локально и автоматически синхронизируются при разрешении доступа."
        default:
            return "Не удалось подключиться к iCloud. Данные сохраняются локально и автоматически синхронизируются при восстановлении связи."
        }
    }
}

// MARK: - UI Components

struct CloudKitStatusView: View {
    @ObservedObject var cloudKitService: CloudKitService
    
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: cloudKitService.statusIcon)
                .foregroundColor(cloudKitService.statusColor)
                .font(.caption)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(cloudKitService.statusDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if cloudKitService.isCloudKitAvailable {
                    Text("SwiftData автоматически синхронизирует данные")
                        .font(.caption2)
                        .foregroundColor(.green)
                } else {
                    Text("Данные сохраняются локально и защищены")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            if !cloudKitService.isCloudKitAvailable {
                Button("Проверить") {
                    Task { await cloudKitService.checkAccountStatus() }
                }
                .font(.caption)
                .foregroundColor(.blue)
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
