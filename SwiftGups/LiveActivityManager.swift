import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

@MainActor
final class LiveActivityManager: ObservableObject {
    private var refreshTask: Task<Void, Never>?
    private var periodicRefreshTask: Task<Void, Never>?
    
    private var cachedSchedule: Schedule?
    private var cachedGroupId: String?
    private var cachedGroupName: String?
    
    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: LiveActivitySettings.enabledKey)
    }
    
    func setEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: LiveActivitySettings.enabledKey)
        
        if enabled {
            refreshNow()
            // Планируем фоновые обновления
            if #available(iOS 13.0, *) {
                BackgroundTaskManager.shared.scheduleBackgroundRefresh()
            }
        } else {
            stopAll()
            if #available(iOS 13.0, *) {
                BackgroundTaskManager.shared.cancelAllTasks()
            }
        }
    }
    
    func updateSchedule(_ schedule: Schedule?) {
        cachedSchedule = schedule
        if schedule == nil {
            stopAll()
        } else {
            refreshNow()
        }
    }
    
    func updateGroup(groupId: String?, groupName: String?) {
        cachedGroupId = groupId
        cachedGroupName = groupName
        
        // Сохраняем в UserDefaults для доступа из фона
        if let groupId = groupId, !groupId.isEmpty,
           let groupName = groupName, !groupName.isEmpty {
            UserDefaults.standard.set(groupId, forKey: "liveActivity.groupId")
            UserDefaults.standard.set(groupName, forKey: "liveActivity.groupName")
        } else {
            UserDefaults.standard.removeObject(forKey: "liveActivity.groupId")
            UserDefaults.standard.removeObject(forKey: "liveActivity.groupName")
        }
        
        if (groupId ?? "").isEmpty || (groupName ?? "").isEmpty {
            stopAll()
            if #available(iOS 13.0, *) {
                BackgroundTaskManager.shared.cancelAllTasks()
            }
        } else {
            refreshNow()
        }
    }
    
    func refreshNow(date: Date = Date()) {
        guard isEnabled else {
            stopAll()
            return
        }
        
        guard let schedule = cachedSchedule,
              let groupId = cachedGroupId, !groupId.isEmpty,
              let groupName = cachedGroupName, !groupName.isEmpty else {
            return
        }
        
        guard let ctx = schedule.currentOrNextLessonContext(at: date) else {
            stopAll()
            return
        }
        
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            await self.upsertActivity(for: ctx, groupId: groupId, groupName: groupName)
            await self.scheduleNextRefresh(for: ctx, now: date)
        }
        
        // Запускаем периодическое обновление каждую минуту для реакции на изменение времени системы
        startPeriodicRefresh()
    }
    
    private func startPeriodicRefresh() {
        periodicRefreshTask?.cancel()
        periodicRefreshTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000) // Каждую минуту
                if self.isEnabled {
                    await self.refreshNow()
                }
            }
        }
    }
    
    func stopAll() {
        refreshTask?.cancel()
        refreshTask = nil
        periodicRefreshTask?.cancel()
        periodicRefreshTask = nil
        
#if canImport(ActivityKit)
        if #available(iOS 16.1, *) {
            Task {
                for activity in Activity<CurrentLessonActivityAttributes>.activities {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
#endif
    }
    
    private func scheduleNextRefresh(for ctx: ScheduleLessonContext, now: Date) async {
        // Когда обновляться:
        // - если сейчас идёт пара -> в её конец (чтобы переключиться на следующую/завершить)
        // - если показываем "следующую" -> в её начало (чтобы переключиться в "current")
        let nextDate: Date
        switch ctx.kind {
        case .current:
            nextDate = ctx.endDate
        case .next:
            nextDate = ctx.startDate
        }
        
        // Небольшой буфер, чтобы гарантированно "перешли" границу.
        let fireAt = nextDate.addingTimeInterval(1)
        let delay = max(1, fireAt.timeIntervalSince(now))
        
        // Планируем фоновое обновление на время перехода пары
        if #available(iOS 13.0, *) {
            BackgroundTaskManager.shared.scheduleRefresh(at: fireAt)
        }
        
        do {
            try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        } catch {
            return
        }
        
        refreshNow(date: Date())
    }
    
    private func upsertActivity(for ctx: ScheduleLessonContext, groupId: String, groupName: String) async {
#if canImport(ActivityKit)
        guard #available(iOS 16.1, *) else { return }

        // --- Поиск следующей пары ---
        var nextLesson: Lesson? = nil
        var nextCtx: ScheduleLessonContext? = nil
        if let schedule = cachedSchedule {
            let now = Date()
            // ищем следующую пару после endDate текущей
            nextCtx = schedule.currentOrNextLessonContext(at: ctx.endDate.addingTimeInterval(1))
            if let next = nextCtx, next.kind == .next {
                nextLesson = next.lesson
            }
        }

        let attributes = CurrentLessonActivityAttributes(groupId: groupId, groupName: groupName)
        let state = CurrentLessonActivityAttributes.ContentState(
            kind: ctx.kind.rawValue,
            pairNumber: ctx.lesson.pairNumber,
            subject: ctx.lesson.subject,
            room: ctx.lesson.room,
            startDate: ctx.startDate,
            endDate: ctx.endDate,
            // ниже: next-пара, если есть
            nextPairNumber: nextLesson?.pairNumber,
            nextSubject: nextLesson?.subject,
            nextRoom: nextLesson?.room,
            nextStartDate: nextCtx?.startDate,
            nextEndDate: nextCtx?.endDate
        )

        // staleDate - когда данные считаются устаревшими (обновляем каждую минуту)
        let staleDate = Date().addingTimeInterval(60)
        let content = ActivityContent(state: state, staleDate: staleDate)

        if let existing = Activity<CurrentLessonActivityAttributes>.activities.first {
            await existing.update(content)
        } else {
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil)
            } catch {
                // ignore
            }
        }
#else
        _ = (ctx, groupId, groupName)
#endif
    }
}

// MARK: - Activity Attributes

/// Атрибуты Live Activity “текущая пара”.
///
/// NOTE: Для корректного отображения в виджете атрибуты должны совпадать и в widget extension.
struct CurrentLessonActivityAttributes: Codable, Hashable {
    let groupId: String
    let groupName: String
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
extension CurrentLessonActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// "current" | "next"
        var kind: String
        
        var pairNumber: Int
        var subject: String
        var room: String?
        var startDate: Date
        var endDate: Date

        // --- Данные следующей пары (если есть) ---
        var nextPairNumber: Int?
        var nextSubject: String?
        var nextRoom: String?
        var nextStartDate: Date?
        var nextEndDate: Date?
    }
}
#endif

