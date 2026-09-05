import Foundation

/// Условия, в которых собрано и запущено приложение.
enum AppEnvironment {

    /// Сборка для LiveContainer.
    ///
    /// Флаг проставляет `Scripts/build-ipa.sh`: такая сборка идёт без подписи,
    /// а значит и без entitlements.
    static var isLiveContainerBuild: Bool {
#if LIVECONTAINER
        true
#else
        false
#endif
    }

    /// Можно ли вообще обращаться к CloudKit.
    ///
    /// Без entitlement `com.apple.developer.icloud-container-identifiers`
    /// `CKContainer.default()` падает фатально, а зеркалирование SwiftData —
    /// ещё и асинхронно, на `com.apple.coredata.cloudkit.queue`: `ModelContainer`
    /// создаётся успешно, и падает уже очередь CoreData, так что do/catch
    /// вокруг создания контейнера не помогает. Поэтому решаем заранее и
    /// не трогаем CloudKit вовсе.
    static var isCloudKitAvailable: Bool {
        !isLiveContainerBuild
    }

    /// Почему синхронизация выключена — для показа в интерфейсе.
    static var cloudKitUnavailableReason: String? {
        guard !isCloudKitAvailable else { return nil }
        return "Синхронизация с iCloud недоступна в этой сборке. Данные сохраняются на устройстве."
    }
}
