import Foundation
import BackgroundTasks

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Менеджер для выполнения фоновых задач обновления Live Activity
@available(iOS 13.0, *)
final class BackgroundTaskManager {
    static let shared = BackgroundTaskManager()
    
    private let taskIdentifier = "tech.artemev.swiftgups.liveactivity.refresh"
    
    private init() {}
    
    /// Регистрирует обработчик фоновых задач
    func registerBackgroundTasks() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: taskIdentifier,
            using: nil
        ) { [weak self] task in
            self?.handleBackgroundTask(task: task as! BGProcessingTask)
        }
    }
    
    /// Планирует следующее выполнение фоновой задачи
    func scheduleBackgroundRefresh() {
        // Отменяем старые задачи перед планированием, чтобы избежать ошибки "too many pending tasks"
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        
        // Планируем обновление каждые 15-30 минут (система сама выберет оптимальное время)
        // Но также можем запланировать на конкретное время (например, начало/конец пары)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // Не раньше чем через 15 минут
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background task scheduled for Live Activity refresh")
        } catch {
            // Code 1 = BGTaskSchedulerErrorCodeTooManyPendingTaskRequests
            if let bgError = error as? BGTaskScheduler.Error, bgError.code == .tooManyPendingTaskRequests {
                print("⚠️ Too many pending tasks (this is normal in simulator), skipping")
            } else {
                print("❌ Failed to schedule background task: \(error)")
            }
        }
    }
    
    /// Планирует обновление на конкретное время (например, начало/конец пары)
    func scheduleRefresh(at date: Date) {
        // Отменяем старые задачи перед планированием новых
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false
        request.earliestBeginDate = date
        
        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background task scheduled for \(date)")
        } catch {
            if let bgError = error as? BGTaskScheduler.Error, bgError.code == .tooManyPendingTaskRequests {
                print("⚠️ Too many pending tasks (this is normal in simulator), skipping schedule at \(date)")
            } else {
                print("❌ Failed to schedule background task at \(date): \(error)")
            }
        }
    }
    
    /// Отменяет все запланированные фоновые задачи
    func cancelAllTasks() {
        BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: taskIdentifier)
        print("🛑 All background tasks cancelled")
    }
    
    /// Обработчик фоновой задачи
    private func handleBackgroundTask(task: BGProcessingTask) {
        print("🔄 Background task started: Live Activity refresh")
        
        // Устанавливаем обработчик отмены
        task.expirationHandler = {
            print("⏰ Background task expired")
            task.setTaskCompleted(success: false)
        }
        
        // Выполняем обновление Live Activity
        Task {
            do {
                await refreshLiveActivityInBackground()
                task.setTaskCompleted(success: true)
                print("✅ Background task completed successfully")
                
                // Планируем следующее обновление
                scheduleBackgroundRefresh()
            } catch {
                print("❌ Background task failed: \(error)")
                task.setTaskCompleted(success: false)
            }
        }
    }
    
    /// Обновляет Live Activity в фоновом режиме
    private func refreshLiveActivityInBackground() async {
        // Проверяем, включена ли Live Activity
        guard UserDefaults.standard.bool(forKey: LiveActivitySettings.enabledKey) else {
            print("⚠️ Live Activity is disabled, skipping refresh")
            return
        }
        
        // Получаем сохраненные данные пользователя
        guard let groupId = UserDefaults.standard.string(forKey: "liveActivity.groupId"),
              !groupId.isEmpty,
              let groupName = UserDefaults.standard.string(forKey: "liveActivity.groupName"),
              !groupName.isEmpty else {
            print("⚠️ No group data found in UserDefaults, skipping refresh")
            return
        }
        
        print("🔄 Refreshing Live Activity for group: \(groupName) (\(groupId))")
        
        // Загружаем расписание
        let now = Date()
        
        // Загружаем расписание на неделю вперед
        let endDate = now.addingTimeInterval(7 * 24 * 60 * 60)
        
        do {
            // Создаем API клиент и загружаем расписание на MainActor
            let schedule = try await MainActor.run {
                let apiClient = DVGUPSAPIClient()
                return apiClient
            }.fetchSchedule(
                for: groupId,
                startDate: now,
                endDate: endDate
            )
            
            // Обновляем Live Activity (метод сам выполнится на MainActor)
            await updateLiveActivityWithSchedule(schedule, groupId: groupId, groupName: groupName)
            
        } catch {
            print("❌ Failed to fetch schedule in background: \(error)")
        }
    }
    
    /// Обновляет Live Activity с новым расписанием
    @MainActor
    private func updateLiveActivityWithSchedule(_ schedule: Schedule, groupId: String, groupName: String) async {
#if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }
        
        let now = Date()
        
        // Получаем текущую или следующую пару
        guard let ctx = schedule.currentOrNextLessonContext(at: now) else {
            // Если нет пар, завершаем Live Activity
            if let existing = Activity<CurrentLessonActivityAttributes>.activities.first {
                await existing.end(nil, dismissalPolicy: .immediate)
            }
            return
        }
        
        // Поиск следующей пары
        var nextLesson: Lesson? = nil
        var nextCtx: ScheduleLessonContext? = nil
        let nextCtxCandidate = schedule.currentOrNextLessonContext(at: ctx.endDate.addingTimeInterval(1))
        if let next = nextCtxCandidate, next.kind == .next {
            nextLesson = next.lesson
            nextCtx = next
        }
        
        let attributes = CurrentLessonActivityAttributes(groupId: groupId, groupName: groupName)
        let state = CurrentLessonActivityAttributes.ContentState(
            kind: ctx.kind.rawValue,
            pairNumber: ctx.lesson.pairNumber,
            subject: ctx.lesson.subject,
            room: ctx.lesson.room,
            startDate: ctx.startDate,
            endDate: ctx.endDate,
            nextPairNumber: nextLesson?.pairNumber,
            nextSubject: nextLesson?.subject,
            nextRoom: nextLesson?.room,
            nextStartDate: nextCtx?.startDate,
            nextEndDate: nextCtx?.endDate
        )
        
        let staleDate = Date().addingTimeInterval(60)
        let content = ActivityContent(state: state, staleDate: staleDate)
        
        if let existing = Activity<CurrentLessonActivityAttributes>.activities.first {
            await existing.update(content)
            print("✅ Live Activity updated in background")
        } else {
            // Если активности нет, создаем новую
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
                print("✅ Live Activity created in background")
            } catch {
                print("❌ Failed to create Live Activity in background: \(error)")
            }
        }
#else
        _ = (schedule, groupId, groupName)
#endif
    }
}
