import Foundation

/// Сервис для управления расписанием
@MainActor
class ScheduleService: ObservableObject {
    
    @Published var faculties: [Faculty] = []
    @Published var selectedFaculty: Faculty?
    @Published var selectedGroup: Group?
    @Published var currentSchedule: Schedule?
    @Published var selectedDate: Date = Date()

    /// Единый справочник групп: вуз (новый API) плюс техникумы (старый).
    ///
    /// Именно по нему идёт выбор группы — без предварительного выбора института.
    @Published var allGroups: [Group] = []
    @Published var isLoadingDirectory = false
    @Published var directoryError: String?

    /// Календарь учебных недель из нового API. Пустой — работаем по календарным неделям.
    @Published var weeks: [ScheduleWeek] = []

    private var didLoadWeeks = false

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
    @Published var isLoadingSchedule = false

    var isLoading: Bool { isLoadingFaculties || isLoadingDirectory || isLoadingSchedule }
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
            // Список институтов нужен только чтобы подписывать группы и добирать
            // техникумы со старого API. Сам по себе он больше ничего не выбирает.
            faculties = result.faculties
            didLoadFaculties = true

            // Кэшируем для оффлайн-режима
            cache.write(faculties, for: .faculties)

            // Институт следует за выбранной группой, а не наоборот, поэтому
            // умолчания тут больше нет — только обновление ссылки на объект.
            if let selected = selectedFaculty {
                selectedFaculty = faculties.first(where: { $0.id == selected.id }) ?? selectedFaculty
            }
        } catch {
            // Оффлайн: пробуем показать то, что было сохранено ранее.
            if let cached: [Faculty] = cache.read([Faculty].self, for: .faculties), !cached.isEmpty {
                faculties = cached
                didLoadFaculties = true
                errorMessage = nil
            } else {
                // Институты — вспомогательные данные: без них справочник групп
                // всё равно грузится, просто группы останутся без подписи института.
                // Поэтому в общий баннер ошибку не выводим, иначе пользователь
                // видит красное сообщение при полностью рабочем приложении.
                didLoadFaculties = true
                print("⚠️ Список институтов недоступен: \(error.localizedDescription)")
            }
        }
        
        isLoadingFaculties = false
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
                endDate: selectedDate.addingTimeInterval(7 * 24 * 60 * 60), // Неделя
                groupName: group.name,
                weekNumber: week(containing: selectedDate)?.id
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
                endDate: endDate,
                groupName: selectedGroup?.id == groupId ? selectedGroup?.name : nil,
                weekNumber: week(containing: startDate)?.id
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
    
    /// Выбирает группу и загружает её недельное расписание
    func selectGroup(_ group: Group) {
        selectedGroup = group
        // Группа могла прийти из общего поиска по вузу — подтягиваем её институт.
        if !group.facultyId.isEmpty,
           selectedFaculty?.id != group.facultyId,
           let faculty = faculties.first(where: { $0.id == group.facultyId }) {
            selectedFaculty = faculty
        }
        currentSchedule = nil
        scheduleDataSource = .network
        scheduleNotice = nil
        isLoadingSchedule = true
        
        Task {
            await loadWeekSchedule() // Загружаем расписание на всю неделю
        }
    }
    
    /// Восстанавливает сохранённый выбор пользователя и грузит его расписание.
    ///
    /// Группу ищем в общем справочнике: сначала по ID, затем по названию — после
    /// переезда на новый API ID группы мог смениться. Расписанию достаточно ID,
    /// поэтому в крайнем случае собираем группу из сохранённых данных.
    func restoreSelection(facultyId: String, groupId: String, groupName: String) async {
        guard !groupId.isEmpty else { return }

        await ensureGroupDirectoryLoaded()

        if let group = group(id: groupId, name: groupName) {
            selectGroup(group)
            return
        }

        // Справочник не загрузился или группа из него пропала — расписанию
        // достаточно ID, поэтому собираем группу из сохранённых данных.
        print("⚠️ Группа \(groupId) не найдена в справочнике — грузим расписание по сохранённому ID")
        selectGroup(Group(id: groupId, name: groupName, fullName: "", facultyId: facultyId))
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
        errorMessage = nil
    }
    
    // MARK: - Единый справочник групп

    /// Загружает справочник один раз за сессию.
    func ensureGroupDirectoryLoaded() async {
        guard allGroups.isEmpty, !isLoadingDirectory else { return }
        await loadGroupDirectory()
    }

    /// Загружает единый справочник групп: вуз (новый API) плюс техникумы (старый).
    ///
    /// Справочник грузится целиком и кэшируется, поэтому поиск потом идёт
    /// локально — мгновенно и без сети. Пользователю не нужно знать, на каком
    /// API живёт его группа, и не нужно сначала выбирать институт.
    func loadGroupDirectory() async {
        isLoadingDirectory = true
        directoryError = nil
        defer { isLoadingDirectory = false }

        // Названия институтов нужны, чтобы подписать группы и добрать техникумы.
        await ensureFacultiesLoaded()

        let directory = await apiClient.fetchCombinedGroupDirectory(faculties: faculties)

        guard !directory.isEmpty else {
            if let cached: [Group] = cache.read([Group].self, for: .groupDirectory), !cached.isEmpty {
                allGroups = cached
                print("📦 Справочник групп взят из кэша: \(cached.count)")
            } else {
                directoryError = "Не удалось загрузить список групп. Проверьте соединение и повторите."
            }
            return
        }

        allGroups = directory
        cache.write(directory, for: .groupDirectory)
        print("✅ Справочник групп загружен: \(directory.count)")
    }

    /// Группы под поисковый запрос и (необязательный) фильтр по институту.
    ///
    /// Поиск локальный: справочник уже целиком в памяти. Совпадение по началу
    /// названия поднимается наверх — набирая «БОД21», человек ищет группу,
    /// а не специальность, в которой встретилась эта подстрока.
    func filteredGroups(matching searchText: String, facultyId: String? = nil) -> [Group] {
        var result = allGroups

        if let facultyId, !facultyId.isEmpty {
            result = result.filter { $0.facultyId == facultyId }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }

        let matches = result.filter { group in
            group.name.localizedCaseInsensitiveContains(query) ||
            group.fullName.localizedCaseInsensitiveContains(query)
        }

        return matches.sorted { lhs, rhs in
            let lhsPrefix = lhs.name.lowercased().hasPrefix(query.lowercased())
            let rhsPrefix = rhs.name.lowercased().hasPrefix(query.lowercased())
            if lhsPrefix != rhsPrefix { return lhsPrefix }
            return lhs.name.localizedCompare(rhs.name) == .orderedAscending
        }
    }

    /// Институты, у которых в справочнике есть хотя бы одна группа.
    ///
    /// Показывать в фильтре институт без групп бессмысленно — по нему всегда
    /// будет пусто.
    var facultiesWithGroups: [Faculty] {
        let ids = Set(allGroups.map { $0.facultyId })
        return faculties.filter { ids.contains($0.id) }
    }

    /// Название института группы — для подписи в списке.
    func facultyName(for group: Group) -> String? {
        guard !group.facultyId.isEmpty else { return nil }
        return faculties.first { $0.id == group.facultyId }?.name
    }

    /// Группа из справочника по ID (или по названию, если ID изменился).
    func group(id: String, name: String = "") -> Group? {
        if let byId = allGroups.first(where: { $0.id == id }) { return byId }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        return allGroups.first { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }
    }

    // MARK: - Учебные недели (новый API)

    /// Загружает календарь учебных недель (одна попытка за сессию).
    ///
    /// Попытка засчитывается и при неудаче: расписание ждёт этот запрос,
    /// и повторять его на каждой смене недели — только тормозить загрузку.
    func ensureWeeksLoaded() async {
        guard !didLoadWeeks else { return }
        didLoadWeeks = true
        await loadWeeks()
    }

    /// Загружает календарь учебных недель.
    ///
    /// Недели — вспомогательные данные: если эндпоинта нет (старый API техникумов),
    /// приложение продолжает работать по календарным неделям.
    func loadWeeks() async {
        do {
            let loaded = try await apiClient.fetchWeeks()
            guard !loaded.isEmpty else { return }
            weeks = loaded
            cache.write(loaded, for: .weeks)
        } catch {
            if let cached: [ScheduleWeek] = cache.read([ScheduleWeek].self, for: .weeks), !cached.isEmpty {
                weeks = cached
            } else {
                print("⚠️ Weeks calendar unavailable: \(error.localizedDescription)")
            }
        }
    }

    /// Учебная неделя, в которую попадает дата.
    func week(containing date: Date) -> ScheduleWeek? {
        weeks.first { $0.contains(date) }
    }

    /// Понедельник недели: из календаря вуза, иначе — вычисленный локально.
    private func weekStart(for date: Date) -> Date? {
        if let week = week(containing: date) { return week.startDate }

        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7 // Преобразуем в систему где понедельник = 0
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: date)
    }

    /// Конец недели: из календаря вуза, иначе — понедельник + 6 дней.
    private func weekEnd(for date: Date, start: Date) -> Date? {
        if let week = week(containing: date) { return week.endDate }
        return Calendar.current.date(byAdding: .day, value: 6, to: start)
    }


    /// Загружает расписание на неделю для выбранной группы
    func loadWeekSchedule() async {
        guard let group = selectedGroup else {
            errorMessage = "Группа не выбрана"
            return
        }
        
        // Границы недели берём из календаря вуза (новый API), иначе считаем сами.
        await ensureWeeksLoaded()

        guard let startOfWeek = weekStart(for: selectedDate) else {
            errorMessage = "Ошибка вычисления начала недели"
            return
        }

        guard let endOfWeek = weekEnd(for: selectedDate, start: startOfWeek) else {
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
                endDate: endOfWeek,
                groupName: group.name,
                weekNumber: week(containing: selectedDate)?.id
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
        selectDate(adjacentWeekDate(offset: -1))
    }

    /// Переходит к следующей неделе
    func nextWeek() {
        selectDate(adjacentWeekDate(offset: 1))
    }

    /// Дата в соседней неделе.
    ///
    /// Если календарь вуза загружен — шагаем по его неделям (они могут быть
    /// неравномерными, например вокруг каникул), иначе просто ±7 дней.
    private func adjacentWeekDate(offset: Int) -> Date {
        if let current = week(containing: selectedDate),
           let index = weeks.firstIndex(where: { $0.id == current.id }) {
            let neighbour = index + offset
            if weeks.indices.contains(neighbour) {
                return weeks[neighbour].startDate
            }
        }

        return Calendar.current.date(byAdding: .weekOfYear, value: offset, to: selectedDate) ?? selectedDate
    }

    /// Переходит к текущей неделе
    func goToCurrentWeek() {
        selectDate(Date())
    }
    
    /// Название учебной недели из календаря вуза («4 неделя»), если оно известно.
    var currentWeekTitle: String? {
        week(containing: selectedDate)?.name
    }

    /// Возвращает строку с диапазоном текущей недели
    func currentWeekRange() -> String {
        guard let startOfWeek = weekStart(for: selectedDate),
              let endOfWeek = weekEnd(for: selectedDate, start: startOfWeek) else {
            return "Неизвестная неделя"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM"
        formatter.locale = Locale(identifier: "ru_RU")
        
        let startString = formatter.string(from: startOfWeek)
        let endString = formatter.string(from: endOfWeek)
        
        return "\(startString) - \(endString)"
    }
    
    /// Обновляет данные: расписание выбранной группы, иначе — справочник групп.
    func refresh() async {
        if selectedGroup != nil {
            await loadWeekSchedule()
        } else {
            await loadGroupDirectory()
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
