import Foundation

/// Сервис для управления расписанием
@MainActor
class ScheduleService: ObservableObject {
    
    @Published var faculties: [Faculty] = Faculty.allFaculties
    @Published var selectedFaculty: Faculty?
    @Published var groups: [Group] = []
    @Published var selectedGroup: Group?
    @Published var currentSchedule: Schedule?
    @Published var selectedDate: Date = Date()
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let apiClient: DVGUPSAPIClient
    
    init() {
        self.apiClient = DVGUPSAPIClient()
        // По умолчанию выбираем Институт управления, автоматизации и телекоммуникаций
        self.selectedFaculty = faculties.first { $0.id == "2" }
    }
    
    init(apiClient: DVGUPSAPIClient) {
        self.apiClient = apiClient
        // По умолчанию выбираем Институт управления, автоматизации и телекоммуникаций
        self.selectedFaculty = faculties.first { $0.id == "2" }
    }
    
    /// Загружает список групп для выбранного факультета
    func loadGroups() async {
        guard let faculty = selectedFaculty else {
            errorMessage = "Факультет не выбран"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let fetchedGroups = try await apiClient.fetchGroups(for: faculty.id, date: selectedDate)
            groups = fetchedGroups
            selectedGroup = nil // Сбрасываем выбранную группу
        } catch {
            errorMessage = error.localizedDescription
            groups = []
        }
        
        isLoading = false
    }
    
    /// Загружает список групп для конкретного факультета
    func loadGroups(for facultyId: String, date: Date? = nil) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let targetDate = date ?? selectedDate
            let fetchedGroups = try await apiClient.fetchGroups(for: facultyId, date: targetDate)
            groups = fetchedGroups
            selectedGroup = nil
        } catch {
            errorMessage = error.localizedDescription
            groups = []
        }
        
        isLoading = false
    }
    
    /// Загружает расписание для выбранной группы
    func loadSchedule() async {
        guard let group = selectedGroup else {
            errorMessage = "Группа не выбрана"
            return
        }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let schedule = try await apiClient.fetchSchedule(
                for: group.id, 
                startDate: selectedDate,
                endDate: selectedDate.addingTimeInterval(7 * 24 * 60 * 60) // Неделя
            )
            currentSchedule = schedule
        } catch {
            errorMessage = error.localizedDescription
            currentSchedule = nil
        }
        
        isLoading = false
    }
    
    /// Загружает расписание для конкретной группы и даты
    func loadSchedule(for groupId: String, startDate: Date, endDate: Date? = nil) async {
        isLoading = true
        errorMessage = nil
        
        do {
            let schedule = try await apiClient.fetchSchedule(
                for: groupId, 
                startDate: startDate, 
                endDate: endDate
            )
            currentSchedule = schedule
        } catch {
            errorMessage = error.localizedDescription
            currentSchedule = nil
        }
        
        isLoading = false
    }
    
    /// Выбирает факультет и загружает его группы
    func selectFaculty(_ faculty: Faculty) {
        selectedFaculty = faculty
        selectedGroup = nil
        currentSchedule = nil
        groups = []
        
        Task {
            await loadGroups()
        }
    }
    
    /// Выбирает группу и загружает её недельное расписание
    func selectGroup(_ group: Group) {
        selectedGroup = group
        currentSchedule = nil
        
        Task {
            await loadWeekSchedule() // Загружаем расписание на всю неделю
        }
    }
    
    /// Изменяет выбранную дату и обновляет данные
    func selectDate(_ date: Date) {
        selectedDate = date
        
        Task {
            // Перезагружаем группы для новой даты
            if selectedFaculty != nil {
                await loadGroups()
            }
            
            // Если группа выбрана, перезагружаем недельное расписание
            if selectedGroup != nil {
                await loadWeekSchedule()
            }
        }
    }
    
    /// Очищает все выбранные данные
    func clearSelection() {
        selectedFaculty = nil
        selectedGroup = nil
        currentSchedule = nil
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
        
        isLoading = true
        errorMessage = nil
        
        do {
            let schedule = try await apiClient.fetchSchedule(
                for: group.id,
                startDate: startOfWeek,
                endDate: endOfWeek
            )
            currentSchedule = schedule
        } catch {
            errorMessage = error.localizedDescription
            currentSchedule = nil
        }
        
        isLoading = false
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
    
    /// Обновляет данные - загружает группы для выбранного факультета
    func refresh() async {
        await loadGroups()
    }
}