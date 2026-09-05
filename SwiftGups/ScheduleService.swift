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

    /// Результаты серверного поиска групп (новый API `/groups/options?q=`).
    @Published var groupSearchResults: [Group] = []
    @Published var isSearchingGroups = false
    /// Есть ли ещё страницы под текущий запрос.
    @Published var groupSearchHasMore = false
    /// Календарь учебных недель из нового API. Пустой — работаем по календарным неделям.
    @Published var weeks: [ScheduleWeek] = []

    /// Полный справочник групп вуза — страховка для поиска без сети.
    private var groupDirectory: [Group] = []
    private var groupSearchQuery: String = ""
    private var groupSearchPage: Int = 1
    private var groupSearchTask: Task<Void, Never>?
    private var didLoadWeeks = false

    /// Пауза перед запросом, чтобы не дёргать сервер на каждую букву.
    private static let groupSearchDebounce: UInt64 = 300_000_000
    private static let groupSearchPageSize = 50

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
            await refreshGroupDirectoryCache()

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
        clearGroupSearch()
        isLoadingGroups = true

        Task {
            await loadGroups()
        }
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
    /// После переезда групп вуза на новый справочник сохранённый институт может
    /// больше не содержать нужную группу (или сам институт мог исчезнуть).
    /// Поэтому ищем группу по цепочке: список института → справочник вуза по ID →
    /// справочник по названию. Расписанию достаточно ID группы, так что в крайнем
    /// случае собираем группу из сохранённых данных.
    func restoreSelection(facultyId: String, groupId: String, groupName: String) async {
        guard !groupId.isEmpty else { return }

        await ensureFacultiesLoaded()

        if let faculty = faculties.first(where: { $0.id == facultyId }) {
            selectedFaculty = faculty
            selectedGroup = nil
            currentSchedule = nil
            groups = []
            await loadGroups()

            if let group = groups.first(where: { $0.id == groupId }) {
                selectGroup(group)
                return
            }
        }

        if let group = await findGroupInDirectory(id: groupId, name: groupName) {
            print("↩️ Группа \(groupId) найдена в справочнике вуза, институт обновлён")
            selectGroup(group)
            return
        }

        print("⚠️ Группа \(groupId) не найдена в справочниках — грузим расписание по сохранённому ID")
        selectGroup(Group(id: groupId, name: groupName, fullName: "", facultyId: facultyId))
    }

    private func findGroupInDirectory(id: String, name: String) async -> Group? {
        if let directory = try? await apiClient.fetchGroupDirectory(), !directory.isEmpty {
            groupDirectory = directory
            cache.write(directory, for: .groupDirectory)
        } else if groupDirectory.isEmpty,
                  let cached: [Group] = cache.read([Group].self, for: .groupDirectory) {
            groupDirectory = cached
        }

        if let byId = groupDirectory.first(where: { $0.id == id }) { return byId }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        return groupDirectory.first { $0.name.caseInsensitiveCompare(trimmedName) == .orderedSame }
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
        clearGroupSearch()
    }
    
    /// Возвращает отфильтрованные группы по поисковому запросу.
    ///
    /// Сначала показываем совпадения в уже загруженном списке факультета,
    /// затем — то, что нашёл сервер по всему вузу (новый API `/groups/options?q=`).
    func filteredGroups(searchText: String) -> [Group] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return groups }

        let local = groups.filter { group in
            group.name.localizedCaseInsensitiveContains(query) ||
            group.fullName.localizedCaseInsensitiveContains(query)
        }

        guard !groupSearchResults.isEmpty else { return local }

        var seen = Set(local.map { $0.id })
        return local + groupSearchResults.filter { seen.insert($0.id).inserted }
    }

    // MARK: - Поиск групп по всему вузу (новый API)

    /// Запускает серверный поиск групп с задержкой (debounce).
    ///
    /// Новый справочник ищет по всему вузу сразу, поэтому группу можно найти,
    /// даже если выбран не тот институт (или институт вообще не выбран).
    func searchGroups(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        groupSearchTask?.cancel()
        groupSearchQuery = trimmed
        groupSearchPage = 1

        // Односимвольный запрос вернёт полсправочника — ждём осмысленного ввода.
        guard trimmed.count >= 2 else {
            groupSearchResults = []
            groupSearchHasMore = false
            isSearchingGroups = false
            return
        }

        let debounce = ScheduleService.groupSearchDebounce
        isSearchingGroups = true
        groupSearchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: debounce)
            guard !Task.isCancelled else { return }
            await self?.performGroupSearch(query: trimmed, page: 1, replacing: true)
        }
    }

    /// Догружает следующую страницу результатов поиска.
    func loadMoreGroupSearchResults() {
        guard groupSearchHasMore, !isSearchingGroups, !groupSearchQuery.isEmpty else { return }

        let query = groupSearchQuery
        let nextPage = groupSearchPage + 1

        isSearchingGroups = true
        groupSearchTask?.cancel()
        groupSearchTask = Task { [weak self] in
            await self?.performGroupSearch(query: query, page: nextPage, replacing: false)
        }
    }

    private func performGroupSearch(query: String, page: Int, replacing: Bool) async {
        do {
            let result = try await apiClient.fetchGroupOptions(
                query: query,
                page: page,
                limit: ScheduleService.groupSearchPageSize
            )

            // Пока шёл запрос, пользователь мог набрать что-то другое —
            // тогда результат уже неактуален, а флаг загрузки принадлежит новому поиску.
            guard !Task.isCancelled, groupSearchQuery == query else { return }

            if replacing {
                groupSearchResults = result.groups
            } else {
                var seen = Set(groupSearchResults.map { $0.id })
                groupSearchResults += result.groups.filter { seen.insert($0.id).inserted }
            }

            groupSearchPage = page
            groupSearchHasMore = result.hasMore
            isSearchingGroups = false
        } catch {
            guard !Self.isCancelled(error), groupSearchQuery == query else { return }

            // Поиск — вспомогательный путь: локальная фильтрация продолжает работать,
            // поэтому ошибку не выводим в общий баннер.
            print("❌ Group search failed for \"\(query)\": \(error.localizedDescription)")
            groupSearchHasMore = false
            if replacing {
                groupSearchResults = offlineGroupMatches(for: query)
            }
            isSearchingGroups = false
        }
    }

    /// Поиск по сохранённому справочнику, когда сервер недоступен.
    private func offlineGroupMatches(for query: String) -> [Group] {
        if groupDirectory.isEmpty,
           let cached: [Group] = cache.read([Group].self, for: .groupDirectory) {
            groupDirectory = cached
        }

        return groupDirectory.filter { group in
            group.name.localizedCaseInsensitiveContains(query) ||
            group.fullName.localizedCaseInsensitiveContains(query)
        }
    }

    /// Обновляет сохранённый справочник групп.
    ///
    /// Клиент держит справочник в памяти после первой выгрузки, поэтому
    /// повторный вызов сетевых запросов не делает.
    private func refreshGroupDirectoryCache() async {
        guard let directory = try? await apiClient.fetchGroupDirectory(), !directory.isEmpty else { return }
        groupDirectory = directory
        cache.write(directory, for: .groupDirectory)
    }

    /// Сбрасывает состояние поиска групп.
    func clearGroupSearch() {
        groupSearchTask?.cancel()
        groupSearchTask = nil
        groupSearchQuery = ""
        groupSearchPage = 1
        groupSearchResults = []
        groupSearchHasMore = false
        isSearchingGroups = false
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
