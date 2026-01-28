import Foundation
import UIKit
import SwiftUI

/// Проверяет статус настроек для работы Background Tasks
@available(iOS 13.0, *)
struct BackgroundTasksStatus {
    /// Проверяет, включен ли Background App Refresh для приложения
    static var isBackgroundAppRefreshEnabled: Bool {
        // В iOS нет прямого API для проверки, но можем проверить через UIApplication
        // На самом деле, iOS автоматически управляет этим, но мы можем проверить общий статус
        return UIApplication.shared.backgroundRefreshStatus == .available
    }
    
    /// Получает статус Background App Refresh
    static var backgroundRefreshStatus: BackgroundRefreshStatus {
        return UIApplication.shared.backgroundRefreshStatus.toBackgroundRefreshStatus
    }
    
    /// Открывает настройки iOS для включения Background App Refresh
    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// Статус Background App Refresh
enum BackgroundRefreshStatus {
    case available
    case restricted
    case denied
    
    var description: String {
        switch self {
        case .available:
            return "Включено"
        case .restricted:
            return "Ограничено"
        case .denied:
            return "Отключено"
        }
    }
    
    var icon: String {
        switch self {
        case .available:
            return "checkmark.circle.fill"
        case .restricted:
            return "exclamationmark.triangle.fill"
        case .denied:
            return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .available:
            return .green
        case .restricted:
            return .orange
        case .denied:
            return .red
        }
    }
}

extension UIBackgroundRefreshStatus {
    var toBackgroundRefreshStatus: BackgroundRefreshStatus {
        switch self {
        case .available:
            return .available
        case .restricted:
            return .restricted
        case .denied:
            return .denied
        @unknown default:
            return .restricted
        }
    }
}
