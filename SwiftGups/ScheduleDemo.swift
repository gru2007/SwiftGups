import Foundation

/// Демо-класс для тестирования парсера расписания
@MainActor
class ScheduleDemo {
    
    private let apiClient = DVGUPSAPIClient()
    private let scheduleService = ScheduleService()
    
    /// Демонстрирует работу парсера с реальными данными
    func runDemo() async {
        print("🎓 Демо парсера расписания ДВГУПС v2.0")
        print(String(repeating: "=", count: 50))
        
        // Тестируем новый функционал
        await testFaculties()
        await testGroupsLoading()
        await testScheduleLoading()
        await testWeekSchedule()
        await testScheduleService()
        
        print("\n✅ Демонстрация завершена!")
    }
    
    /// Тестирует отображение факультетов
    private func testFaculties() async {
        print("\n📚 Тестирование списка факультетов...")
        
        let faculties = Faculty.allFaculties
        print("✅ Загружено \(faculties.count) факультетов:")
        
        for (index, faculty) in faculties.prefix(5).enumerated() {
            print("   \(index + 1). [\(faculty.id)] \(faculty.name)")
        }
        
        if faculties.count > 5 {
            print("   ... и еще \(faculties.count - 5) факультетов")
        }
    }
    
    /// Тестирует загрузку списка групп
    private func testGroupsLoading() async {
        print("\n📋 Тестирование загрузки групп...")
        
        // Тестируем для Института управления, автоматизации и телекоммуникаций (ID: 2)
        let facultyId = "2"
        let facultyName = Faculty.allFaculties.first { $0.id == facultyId }?.name ?? "Неизвестный факультет"
        
        print("🏛️ Факультет: \(facultyName) (ID: \(facultyId))")
        print("📅 Дата: \(DateFormatter.displayDateFormatter.string(from: Date()))")
        
        do {
            let groups = try await apiClient.fetchGroups(for: facultyId, date: Date())
            print("✅ Успешно загружено \(groups.count) групп")
            
            // Показываем первые 5 групп
            for (index, group) in groups.prefix(5).enumerated() {
                print("   \(index + 1). [\(group.id)] \(group.name) - \(group.fullName)")
            }
            
            if groups.count > 5 {
                print("   ... и еще \(groups.count - 5) групп")
            }
            
            // Тестируем с первой группой для следующего теста
            if let firstGroup = groups.first {
                await testSingleGroupSchedule(groupId: firstGroup.id, groupName: firstGroup.name)
            }
            
        } catch {
            print("❌ Ошибка загрузки групп: \(error.localizedDescription)")
        }
    }
    
    /// Тестирует загрузку расписания для конкретной группы
    private func testScheduleLoading() async {
        print("\n📅 Тестирование загрузки расписания...")
        
        // Попробуем с тестовой группой
        let testGroupId = "58031"
        await testSingleGroupSchedule(groupId: testGroupId, groupName: "Тестовая группа")
    }
    
    /// Тестирует загрузку расписания для конкретной группы
    private func testSingleGroupSchedule(groupId: String, groupName: String) async {
        print("\n   🔍 Тестирование группы: \(groupName) (ID: \(groupId))")
        
        do {
            let schedule = try await apiClient.fetchSchedule(for: groupId, startDate: Date())
            print("   ✅ Расписание загружено успешно")
            print("   📊 Статистика:")
            print("      - Группа: \(schedule.groupName)")
            print("      - Период: \(DateFormatter.displayDateFormatter.string(from: schedule.startDate)) - \(DateFormatter.displayDateFormatter.string(from: schedule.endDate))")
            print("      - Дней с занятиями: \(schedule.days.count)")
            
            var totalLessons = 0
            for day in schedule.days {
                totalLessons += day.lessons.count
            }
            print("      - Всего занятий: \(totalLessons)")
            
            // Показываем детали первого дня
            if let firstDay = schedule.days.first {
                print("   📝 Первый день (\(firstDay.weekday), \(DateFormatter.apiDateFormatter.string(from: firstDay.date))):")
                for (index, lesson) in firstDay.lessons.prefix(3).enumerated() {
                    print("      \(index + 1). \(lesson.pairNumber) пара: \(lesson.subject)")
                    print("         Тип: \(lesson.type.rawValue)")
                    print("         Время: \(lesson.timeStart)-\(lesson.timeEnd)")
                    if let teacher = lesson.teacher {
                        print("         Преподаватель: \(teacher.name)")
                    }
                    if let room = lesson.room, !room.isEmpty {
                        print("         Аудитория: \(room)")
                    }
                }
                
                if firstDay.lessons.count > 3 {
                    print("      ... и еще \(firstDay.lessons.count - 3) занятий")
                }
            }
            
        } catch {
            print("   ❌ Ошибка загрузки расписания: \(error.localizedDescription)")
        }
    }
    
    /// Тестирует недельное расписание
    private func testWeekSchedule() async {
        print("\n📆 Тестирование недельного расписания...")
        
        // Вычисляем начало и конец недели
        let calendar = Calendar.current
        let today = Date()
        let weekday = calendar.component(.weekday, from: today)
        let daysFromMonday = (weekday + 5) % 7
        
        guard let startOfWeek = calendar.date(byAdding: .day, value: -daysFromMonday, to: today),
              let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) else {
            print("❌ Ошибка вычисления недели")
            return
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM"
        formatter.locale = Locale(identifier: "ru_RU")
        
        let weekRange = "\(formatter.string(from: startOfWeek)) - \(formatter.string(from: endOfWeek))"
        print("📅 Тестовая неделя: \(weekRange)")
        
        // Тестируем с тестовой группой
        let testGroupId = "58031"
        do {
            let schedule = try await apiClient.fetchSchedule(
                for: testGroupId,
                startDate: startOfWeek,
                endDate: endOfWeek
            )
            
            print("✅ Недельное расписание загружено")
            print("📊 На неделе:")
            print("   - Дней с занятиями: \(schedule.days.count)")
            
            var totalLessons = 0
            for day in schedule.days {
                totalLessons += day.lessons.count
                print("   - \(day.weekday): \(day.lessons.count) занятий")
            }
            print("   - Всего занятий: \(totalLessons)")
            
        } catch {
            print("❌ Ошибка загрузки недельного расписания: \(error.localizedDescription)")
        }
    }
    
    /// Тестирует ScheduleService
    private func testScheduleService() async {
        print("\n🔧 Тестирование ScheduleService...")
        
        // Выбираем факультет
        if let faculty = scheduleService.faculties.first(where: { $0.id == "2" }) {
            print("🏛️ Выбираем факультет: \(faculty.name)")
            scheduleService.selectFaculty(faculty)
            
            // Ждем загрузки групп
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 секунды
            
            print("✅ Загружено \(scheduleService.groups.count) групп через сервис")
            
            if let firstGroup = scheduleService.groups.first {
                print("👥 Выбираем группу: \(firstGroup.name)")
                scheduleService.selectGroup(firstGroup)
                
                // Ждем загрузки расписания
                try? await Task.sleep(nanoseconds: 3_000_000_000) // 3 секунды
                
                if let schedule = scheduleService.currentSchedule {
                    print("✅ Расписание загружено через сервис")
                    print("📊 Дней: \(schedule.days.count)")
                } else if let error = scheduleService.errorMessage {
                    print("❌ Ошибка сервиса: \(error)")
                } else {
                    print("⏳ Расписание еще загружается...")
                }
            }
        }
        
        // Тестируем навигацию по неделям
        print("\n📅 Тестирование навигации по неделям:")
        print("   Текущая неделя: \(scheduleService.currentWeekRange())")
        
        scheduleService.nextWeek()
        print("   Следующая неделя: \(scheduleService.currentWeekRange())")
        
        scheduleService.previousWeek()
        scheduleService.previousWeek()
        print("   Предыдущая неделя: \(scheduleService.currentWeekRange())")
        
        scheduleService.goToCurrentWeek()
        print("   Возврат к текущей: \(scheduleService.currentWeekRange())")
    }
}

// MARK: - Расширение для демонстрационного запуска

extension ScheduleDemo {
    /// Запускает демонстрацию в фоновом режиме
    static func runDemoInBackground() {
        Task {
            let demo = ScheduleDemo()
            await demo.runDemo()
        }
    }
}