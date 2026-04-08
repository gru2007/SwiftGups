import Foundation

/// Сервис для управления расписанием
@MainActor
class ScheduleService: ObservableObject {
    
    @Published var faculties: [Faculty] = []
    @Published var facultiesMissingIDs: [String] = []
    @Published var selectedFaculty: Faculty?
    @Published var groups: [Group] = []
    @Published var selectedGroup: Group?
    @Published var currentSchedule: Schedule?
    @Published var selectedDate: Date = Date()
    
    enum DataSource: Equatable {
        case network
        case cache
    }
    
    /// Источник данных для текущего расписания (для UI баннера "Оффлайн").
    @Published var scheduleDataSource: DataSource = .network
    
    enum ScheduleNotice: Equatable {
        case timeout(seconds: Int)
    }

    enum RecoveryAction: Equatable {
        case connectDVGUPSAccount
        case refreshDVGUPSAccount

        init?(apiError: APIError) {
            switch apiError {
            case .authenticationRequired:
                self = .connectDVGUPSAccount
            case .invalidCredentials:
                self = .refreshDVGUPSAccount
            default:
                return nil
            }
        }
    }
    
    /// Доп. уведомление (например, timeout 8 сек), показываем в верхней плашке.
    @Published var scheduleNotice: ScheduleNotice? = nil
    @Published var recoveryAction: RecoveryAction? = nil
    
    @Published var isLoadingFaculties = false
    @Published var isLoadingGroups = false
    @Published var isLoadingSchedule = false
    
    var isLoading: Bool { isLoadingFaculties || isLoadingGroups || isLoadingSchedule }
    @Published var errorMessage: String?
    
    private let apiClient: DVGUPSAPIClient
    private var didLoadFaculties = false
    private let cache = ScheduleCacheStore()

    private static func isCancelled(_ error: Error) -> Bool {
        if let urlError = error as? URLError, urlError.code == .cancelled {
            return true
        }
        if let apiError = error as? APIError, case .networkError(let underlying) = apiError {
            if let urlError = underlying as? URLError, urlError.code == .cancelled {
                return true
            }
        }
        return false
    }
    
    init() {
        self.apiClient = DVGUPSAPIClient()
    }
    
    init(apiClient: DVGUPSAPIClient) {
        self.apiClient = apiClient
    }
    
    /// Гарантирует, что список институтов загружен хотя бы один раз
    func ensureFacultiesLoaded() async {
        guard !didLoadFaculties else { return }
        await loadFaculties()
    }
    
    /// Загружает список институтов/факультетов с сервера
    func loadFaculties() async {
        isLoadingFaculties = true
        clearTransientState()
        
        do {
            let result = try await apiClient.fetchFaculties()
            // Если API прислал пустой список факультетов — не подменяем статикой.
            // Если API прислал только факультеты без ID — они будут показаны баннером в UI.
            faculties = result.faculties
            facultiesMissingIDs = result.missingIdNames
            didLoadFaculties = true
            
            // Кэшируем для оффлайн-режима
            cache.write(faculties, for: .faculties)
            
            // Выбор дефолтного института (если ещё ничего не выбрано)
            if selectedFaculty == nil {
                selectedFaculty = faculties.first(where: { $0.id == "2" }) ?? faculties.first
            } else if let selected = selectedFaculty {
                // Если selectedFaculty пришел из старого/статического списка — обновим ссылку на объект из актуального массива
                selectedFaculty = faculties.first(where: { $0.id == selected.id }) ?? selectedFaculty
            }
        } catch {
            // Оффлайн: пробуем показать то, что было сохранено ранее.
            if let cached: [Faculty] = cache.read([Faculty].self, for: .faculties), !cached.isEmpty {
                faculties = cached
                facultiesMissingIDs = []
                didLoadFaculties = true
                errorMessage = nil
            } else {
                // По ТЗ: статический список больше не актуален — не используем его.
                facultiesMissingIDs = []
                didLoadFaculties = true
                applyErrorState(error)
            }
        }
        
        isLoadingFaculties = false
    }
    
    /// Загружает список групп для выбранного факультета
    func loadGroups() async {
        guard let faculty = selectedFaculty else {
            errorMessage = "Факультет не выбран"
            return
        }
        
        print("🔄 ScheduleService.loadGroups() started for faculty: \(faculty.id) (\(faculty.name))")
        isLoadingGroups = true
        clearTransientState()
        defer { isLoadingGroups = false }
        
        do {
            let fetchedGroups = try await apiClient.fetchGroups(for: faculty.id)
            print("✅ Successfully fetched \(fetchedGroups.count) groups for faculty \(faculty.id)")
            groups = fetchedGroups
            selectedGroup = nil // Сбрасываем выбранную группу
            
            cache.write(groups, for: .groups(facultyId: faculty.id))
            
            if fetchedGroups.isEmpty {
                print("⚠️ No groups found for faculty \(faculty.id)")
                errorMessage = "Группы для данного факультета не найдены"
            }
        } catch {
            if Self.isCancelled(error) {
                // Не показываем "отменено" пользователю, просто выходим.
                print("⚠️ loadGroups cancelled")
                return
            }
            print("❌ Error fetching groups: \(error.localizedDescription)")
            // Оффлайн: пробуем кэш групп по факультету
            if let cached: [Group] = cache.read([Group].self, for: .groups(facultyId: faculty.id)), !cached.isEmpty {
                groups = cached
                errorMessage = nil
            } else {
                if let apiError = error as? APIError {
                    print("❌ API Error details: \(apiError)")
                }
                applyErrorState(error)
                groups = []
            }
        }

        print("🏁 ScheduleService.loadGroups() finished. Groups count: \(groups.count)")
    }
    
    /// Загружает список групп для конкретного факультета
    func loadGroups(for facultyId: String, date: Date? = nil) async {
        print("🔄 ScheduleService.loadGroups(for: \(facultyId)) started")
        isLoadingGroups = true
        clearTransientState()
        
        do {
            let fetchedGroups = try await apiClient.fetchGroups(for: facultyId)
            print("✅ Successfully fetched \(fetchedGroups.count) groups for faculty \(facultyId)")
            groups = fetchedGroups
            selectedGroup = nil
            
            if fetchedGroups.isEmpty {
                print("⚠️ No groups found for faculty \(facultyId)")
                errorMessage = "Группы для данного факультета не найдены"
            }
        } catch {
            print("❌ Error fetching groups for faculty \(facultyId): \(error.localizedDescription)")
            applyErrorState(error)
            groups = []
        }
        
        isLoadingGroups = false
        print("🏁 ScheduleService.loadGroups(for: \(facultyId)) finished. Groups count: \(groups.count)")
    }
    
    /// Загружает расписание для выбранной группы
    func loadSchedule() async {
        guard let group = selectedGroup else {
            errorMessage = "Группа не выбрана"
            return
        }
        
        isLoadingSchedule = true
        clearTransientState()
        
        do {
            let schedule = try await apiClient.fetchSchedule(
                for: group.id, 
                startDate: selectedDate,
                endDate: selectedDate.addingTimeInterval(7 * 24 * 60 * 60) // Неделя
            )
            currentSchedule = schedule
            scheduleDataSource = .network
            scheduleNotice = nil
        } catch {
            if let apiError = error as? APIError, case .requestTimedOut(let seconds) = apiError {
                scheduleNotice = .timeout(seconds: seconds)
            } else {
                scheduleNotice = nil
            }
            applyErrorState(error)
            currentSchedule = nil
        }
        
        isLoadingSchedule = false
    }
    
    /// Загружает расписание для конкретной группы и даты
    func loadSchedule(for groupId: String, startDate: Date, endDate: Date? = nil) async {
        isLoadingSchedule = true
        clearTransientState()
        
        do {
            let schedule = try await apiClient.fetchSchedule(
                for: groupId, 
                startDate: startDate, 
                endDate: endDate
            )
            currentSchedule = schedule
            scheduleDataSource = .network
            scheduleNotice = nil
        } catch {
            if let apiError = error as? APIError, case .requestTimedOut(let seconds) = apiError {
                scheduleNotice = .timeout(seconds: seconds)
            } else {
                scheduleNotice = nil
            }
            applyErrorState(error)
            currentSchedule = nil
        }
        
        isLoadingSchedule = false
    }
    
    /// Выбирает факультет и загружает его группы
    func selectFaculty(_ faculty: Faculty) {
        print("🎯 ScheduleService.selectFaculty() called for: \(faculty.name) (id: \(faculty.id))")
        selectedFaculty = faculty
        selectedGroup = nil
        currentSchedule = nil
        scheduleDataSource = .network
        scheduleNotice = nil
        recoveryAction = nil
        groups = []
        isLoadingGroups = true
        
        Task {
            await loadGroups()
        }
    }
    
    /// Выбирает группу и загружает её недельное расписание
    func selectGroup(_ group: Group) {
        selectedGroup = group
        currentSchedule = nil
        scheduleDataSource = .network
        scheduleNotice = nil
        isLoadingSchedule = true
        
        Task {
            await loadWeekSchedule() // Загружаем расписание на всю неделю
        }
    }
    
    /// Изменяет выбранную дату и обновляет данные
    func selectDate(_ date: Date) {
        selectedDate = date
        
        Task { [selectedFaculty, selectedGroup] in
            // Группы менять не нужно при смене недели — состав групп не зависит от даты
            // Поэтому перезагружаем только расписание, если группа выбрана
            if selectedGroup != nil {
                await MainActor.run { self.isLoadingSchedule = true }
                await loadWeekSchedule()
            }
        }
    }
    
    /// Очищает все выбранные данные
    func clearSelection() {
        selectedFaculty = nil
        selectedGroup = nil
        currentSchedule = nil
        scheduleDataSource = .network
        scheduleNotice = nil
        groups = []
        errorMessage = nil
    }
    
    /// Возвращает отфильтрованные группы по поисковому запросу
    func filteredGroups(searchText: String) -> [Group] {
        guard !searchText.isEmpty else { return groups }
        
        return groups.filter { group in
            group.name.localizedCaseInsensitiveContains(searchText) ||
            group.fullName.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// Возвращает отфильтрованные факультеты по поисковому запросу
    func filteredFaculties(searchText: String) -> [Faculty] {
        guard !searchText.isEmpty else { return faculties }
        
        return faculties.filter { faculty in
            faculty.name.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    /// Загружает расписание на неделю для выбранной группы
    func loadWeekSchedule() async {
        guard let group = selectedGroup else {
            errorMessage = "Группа не выбрана"
            return
        }
        
        // Вычисляем начало недели (понедельник)
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: selectedDate)
        let daysFromMonday = (weekday + 5) % 7 // Преобразуем в систему где понедельник = 0
        
        guard let startOfWeek = calendar.date(byAdding: .day, value: -daysFromMonday, to: selectedDate) else {
            errorMessage = "Ошибка вычисления начала недели"
            return
        }
        
        guard let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) else {
            errorMessage = "Ошибка вычисления конца недели"
            return
        }
        
        isLoadingSchedule = true
        clearTransientState()
        print("📆 Loading week schedule for group: \(group.id) from \(DateFormatter.apiDateFormatter.string(from: startOfWeek)) to \(DateFormatter.apiDateFormatter.string(from: endOfWeek))")
        defer { isLoadingSchedule = false }
        
        do {
            let schedule = try await apiClient.fetchSchedule(
                for: group.id,
                startDate: startOfWeek,
                endDate: endOfWeek
            )
            currentSchedule = schedule
            scheduleDataSource = .network
            scheduleNotice = nil
            
            let keyDate = DateFormatter.serverDateFormatter.string(from: startOfWeek)
            cache.write(schedule, for: .schedule(groupId: group.id, weekStart: keyDate))
            print("✅ Week schedule loaded: days=\(schedule.days.count) group=\(schedule.groupName)")
        } catch {
            if Self.isCancelled(error) {
                print("⚠️ loadWeekSchedule cancelled")
                return
            }
            let keyDate = DateFormatter.serverDateFormatter.string(from: startOfWeek)
            if let cached: Schedule = cache.read(Schedule.self, for: .schedule(groupId: group.id, weekStart: keyDate)) {
                currentSchedule = cached
                scheduleDataSource = .cache
                errorMessage = nil
                
                if let apiError = error as? APIError, case .requestTimedOut(let seconds) = apiError {
                    scheduleNotice = .timeout(seconds: seconds)
                } else {
                    scheduleNotice = nil
                }
                print("📦 Loaded cached schedule for group \(group.id), week \(keyDate)")
            } else {
                scheduleDataSource = .network
                if let apiError = error as? APIError, case .requestTimedOut(let seconds) = apiError {
                    scheduleNotice = .timeout(seconds: seconds)
                } else {
                    scheduleNotice = nil
                }
                applyErrorState(error)
                currentSchedule = nil
                print("❌ Failed to load week schedule: \(error.localizedDescription)")
            }
        }
    }
    
    /// Переходит к предыдущей неделе
    func previousWeek() {
        guard let newDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate) else {
            return
        }
        selectDate(newDate)
    }
    
    /// Переходит к следующей неделе
    func nextWeek() {
        guard let newDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate) else {
            return
        }
        selectDate(newDate)
    }
    
    /// Переходит к текущей неделе
    func goToCurrentWeek() {
        selectDate(Date())
    }
    
    /// Возвращает строку с диапазоном текущей недели
    func currentWeekRange() -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: selectedDate)
        let daysFromMonday = (weekday + 5) % 7 // Преобразуем в систему где понедельник = 0
        
        guard let startOfWeek = calendar.date(byAdding: .day, value: -daysFromMonday, to: selectedDate),
              let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) else {
            return "Неизвестная неделя"
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM"
        formatter.locale = Locale(identifier: "ru_RU")
        
        let startString = formatter.string(from: startOfWeek)
        let endString = formatter.string(from: endOfWeek)
        
        return "\(startString) - \(endString)"
    }
    
    /// Обновляет данные - загружает группы и расписание
    func refresh() async {
        // Если институты ещё не загружены — начинаем с них
        if !didLoadFaculties {
            await loadFaculties()
            return
        }
        
        // Если есть выбранная группа, перезагружаем её расписание
        if selectedGroup != nil {
            await loadWeekSchedule()
        } else if selectedFaculty != nil {
            // Иначе загружаем группы для выбранного факультета
            await loadGroups()
        }
    }

    private func clearTransientState() {
        errorMessage = nil
        recoveryAction = nil
    }

    private func applyErrorState(_ error: Error) {
        if let apiError = error as? APIError {
            errorMessage = apiError.localizedDescription
            recoveryAction = RecoveryAction(apiError: apiError)
        } else {
            errorMessage = error.localizedDescription
            recoveryAction = nil
        }
    }
}
