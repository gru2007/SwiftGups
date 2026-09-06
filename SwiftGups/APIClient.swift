import Foundation

/// Ошибки API клиента
enum APIError: Error, LocalizedError {
    case invalidURL
    case noData
    case parseError(String)
    case networkError(Error)
    case invalidResponse
    /// Сервер ответил кодом вне 2xx. Код и путь нужны в тексте ошибки:
    /// без них «неверный формат ответа» ничего не говорит ни пользователю,
    /// ни тому, кто будет разбираться по скриншоту.
    case unexpectedStatus(code: Int, path: String)
    case authenticationRequired
    case invalidCredentials
    case groupNotFound
    case facultyNotFound
    case vpnOrBlockedNetwork
    case requestTimedOut(seconds: Int)
    case emptyResponse
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL"
        case .noData:
            return "Нет данных в ответе"
        case .parseError(let message):
            return "Ошибка парсинга: \(message)"
        case .networkError(let error):
            return "Ошибка сети: \(error.localizedDescription)"
        case .invalidResponse:
            return "Неверный формат ответа сервера"
        case .unexpectedStatus(let code, let path):
            return "Сервер ответил \(code) на \(path)"
        case .authenticationRequired:
            return "Для доступа к расписанию нужен вход в ЛК ДВГУПС. Откройте вкладку «Профиль» и добавьте логин и пароль."
        case .invalidCredentials:
            return "Не удалось авторизоваться в ЛК ДВГУПС. Проверьте логин и пароль во вкладке «Профиль»."
        case .groupNotFound:
            return "Группа не найдена"
        case .facultyNotFound:
            return "Факультет не найден"
        case .vpnOrBlockedNetwork:
            return "Не удалось подключиться к серверу. Возможно включен VPN или сеть блокирует доступ к dvgups.ru. Отключите VPN и повторите попытку."
        case .requestTimedOut(let seconds):
            return "Сервер не ответил за \(seconds) сек. Проверьте интернет и потяните вниз, чтобы обновить."
        case .emptyResponse:
            return "Сервер вернул пустой ответ. Потяните вниз, чтобы обновить."
        }
    }

    var isAuthenticationIssue: Bool {
        switch self {
        case .authenticationRequired, .invalidCredentials:
            return true
        default:
            return false
        }
    }
}

/// API клиент для работы с расписанием ДВГУПС
@MainActor
class DVGUPSAPIClient: ObservableObject {
    
    // MARK: - Константы (REST API)
    
    /// Основной публичный домен, который использует веб-версия (см. `dvgups.ru.har`).
    private let primaryBaseURL = URL(string: "https://dvgups.ru")!
    /// Фолбек отключён: используем только `dvgups.ru`, чтобы не удваивать ожидание.
    private let fallbackBaseURL = URL(string: "https://dvgups.ru")!
    
    private let session: URLSession
    private let authService: DVGUPSAuthService
    private let requestTimeoutSeconds: TimeInterval = 8
    /// Справочник групп нового API — выгружается постранично, поэтому кэшируем на время сессии.
    private var cachedGroupDirectory: [Group]?

    // MARK: - Инициализация
    
    init(session: URLSession = .shared, authService: DVGUPSAuthService = .shared) {
        self.session = session
        self.authService = authService
    }
    
    // MARK: - Публичные методы (REST)
    
    struct FacultiesResult {
        let faculties: [Faculty]
        /// Названия институтов/факультетов, которые пришли без ID (их нельзя выбрать/использовать для запроса групп)
        let missingIdNames: [String]
    }
    
    /// Получает список институтов/факультетов (динамически)
    func fetchFaculties() async throws -> FacultiesResult {
        // ВУЗ менял формат отдачи не раз: встречались и «табличка» [[id, name]],
        // и массив объектов, и (сейчас) объект с `items`. Конверт разворачивает
        // список, а элементы декодим в два прохода.
        let data = try await requestData(
            baseURL: primaryBaseURL,
            path: "/api/v1/timetable/faculties",
            queryItems: []
        )

        var faculties: [Faculty] = []
        var missingIdNames: [String] = []

        func add(id rawId: String?, name rawName: String?) {
            let name = (rawName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            // «<НЕТ>» — служебная запись, показывать её пользователю незачем.
            guard !name.isEmpty, !name.hasPrefix("<") else { return }

            let id = (rawId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !id.isEmpty else {
                missingIdNames.append(name)
                return
            }

            faculties.append(Faculty(id: id, name: name))
        }

        struct FacultyDTO: Decodable {
            let id: String?
            let name: String?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = container.decodeLooseString(forKey: .id)
                name = container.decodeLooseString(forKey: .name)
            }

            enum CodingKeys: String, CodingKey { case id, name }
        }

        if let envelope = try? JSONDecoder().decode(APIListEnvelope<FacultyDTO>.self, from: data),
           !envelope.items.isEmpty {
            for dto in envelope.items {
                add(id: dto.id, name: dto.name)
            }
        } else {
            // Формат-«табличка»: data = [[id?, name?], ...]
            let envelope = try JSONDecoder().decode(APIListEnvelope<[String?]>.self, from: data)
            for row in envelope.items {
                add(id: row.count > 0 ? row[0] : nil, name: row.count > 1 ? row[1] : nil)
            }
        }

        // Убираем дубликаты по id, сортируем по названию
        let unique = Dictionary(grouping: faculties, by: { $0.id })
            .compactMap { $0.value.first }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }

        return FacultiesResult(
            faculties: unique,
            missingIdNames: Array(Set(missingIdNames)).sorted()
        )
    }
    
    /// Больше 100 сервер не отдаёт: «limit must not be greater than 100».
    private static let groupDirectoryPageSize = 100
    /// Максимум страниц: страховка от бесконечного цикла,
    /// если сервер всегда отвечает `has_more: true`.
    private static let groupDirectoryMaxPages = 60

    /// Одна страница справочника групп из нового API.
    ///
    /// `query` — серверный поиск по названию группы и специальности
    /// (тот самый параметр `q`, который использует веб-версия).
    func fetchGroupOptions(
        query: String? = nil,
        page: Int = 1,
        limit: Int = 50
    ) async throws -> GroupOptionsPage {
        var queryItems = [
            URLQueryItem(name: "page", value: String(max(1, page))),
            URLQueryItem(name: "limit", value: String(max(1, limit)))
        ]

        if let query = query?.trimmingCharacters(in: .whitespacesAndNewlines), !query.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: query))
        }

        let response: APIEnvelope<GroupOptionsPageDTO> = try await request(
            baseURL: primaryBaseURL,
            path: "/api/v1/timetable/groups/options",
            queryItems: queryItems
        )

        return response.data.makePage(requestedPage: max(1, page), requestedLimit: max(1, limit))
    }

    /// Полный справочник групп вуза (все страницы `/groups/options`).
    ///
    /// Эндпоинт не умеет фильтровать по институту, поэтому выгружаем справочник
    /// целиком и фильтруем на клиенте — заодно получаем мгновенный локальный поиск.
    /// Результат держим в памяти: смена института не должна тянуть его заново.
    func fetchGroupDirectory(forceRefresh: Bool = false) async throws -> [Group] {
        if !forceRefresh, let cached = cachedGroupDirectory, !cached.isEmpty {
            return cached
        }

        var collected: [Group] = []
        var seenIds = Set<String>()
        var page = 1

        while page <= Self.groupDirectoryMaxPages {
            let result = try await fetchGroupOptions(page: page, limit: Self.groupDirectoryPageSize)

            for group in result.groups where !seenIds.contains(group.id) {
                seenIds.insert(group.id)
                collected.append(group)
            }

            guard result.hasMore, !result.groups.isEmpty else { break }
            page += 1
        }

        let directory = collected.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        cachedGroupDirectory = directory
        return directory
    }

    /// Единый справочник групп: вуз плюс техникумы ассоциации.
    ///
    /// Группы вуза переехали в `/groups/options`, техникумы остались на старом
    /// `/groups/by-faculty`, и объединить их может только клиент. Одним списком
    /// они становятся пригодны для общего поиска — пользователю не нужно
    /// заранее знать, на каком API живёт его группа.
    ///
    /// Метод не бросает: частичный справочник полезнее пустого, поэтому упавшие
    /// факультеты просто не попадают в результат.
    func fetchCombinedGroupDirectory(faculties: [Faculty]) async -> [Group] {
        var collected: [Group] = []
        var seenIds = Set<String>()

        func append(_ groups: [Group]) {
            for group in groups where seenIds.insert(group.id).inserted {
                collected.append(group)
            }
        }

        // 1. Новый справочник вуза — основная масса групп.
        let directory = (try? await fetchGroupDirectory()) ?? []
        append(directory)

        // 2. Факультеты, которых в новом справочнике нет, — техникумы на старом API.
        let coveredFacultyIds = Set(directory.map { $0.facultyId }.filter { !$0.isEmpty })
        let legacyFaculties = faculties.filter { !coveredFacultyIds.contains($0.id) }

        if !legacyFaculties.isEmpty {
            let legacyGroups = await withTaskGroup(of: [Group].self) { group in
                for faculty in legacyFaculties {
                    group.addTask { [weak self] in
                        guard let self else { return [] }
                        return (try? await self.fetchLegacyGroups(for: faculty.id)) ?? []
                    }
                }

                var result: [Group] = []
                for await groups in group {
                    result.append(contentsOf: groups)
                }
                return result
            }

            append(legacyGroups)
        }

        return collected.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Список групп факультета/института.
    ///
    /// Группы вуза живут в новом справочнике `/groups/options`, техникумы
    /// ассоциации остались на старом `/groups/by-faculty`. Поэтому сначала
    /// пробуем новый путь, а если по факультету там пусто — идём в старый.
    func fetchGroups(for facultyId: String) async throws -> [Group] {
        let directory: [Group]
        do {
            directory = try await fetchGroupDirectory()
        } catch {
            // Новый справочник недоступен — вся надежда на старый эндпоинт.
            return try await fetchLegacyGroups(for: facultyId)
        }

        let matching = directory.filter { $0.facultyId == facultyId }
        if !matching.isEmpty {
            return matching
        }

        return try await fetchLegacyGroups(for: facultyId)
    }

    /// Старый эндпоинт групп по факультету (техникумы ассоциации).
    func fetchLegacyGroups(for facultyId: String) async throws -> [Group] {
        struct GroupDTO: Decodable {
            let id: String?
            let name: String?
            let field: String?

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                id = container.decodeLooseString(forKey: .id)
                name = container.decodeLooseString(forKey: .name)
                field = container.decodeLooseString(forKey: .field)
            }

            enum CodingKeys: String, CodingKey { case id, name, field }
        }

        // Сервер переименовал параметр в faculty_id и на старое имя отвечает
        // 400 «faculty_id must be a string». Пробуем оба варианта.
        var response: APIListEnvelope<GroupDTO>?
        var lastError: Error?

        for name in ["faculty_id", "facultyId"] {
            do {
                response = try await request(
                    baseURL: primaryBaseURL,
                    path: "/api/v1/timetable/groups/by-faculty",
                    queryItems: [URLQueryItem(name: name, value: facultyId)]
                )
                break
            } catch let error as APIError {
                guard case .unexpectedStatus(let code, _) = error, code == 400 else { throw error }
                lastError = error
            }
        }

        guard let response else { throw lastError ?? APIError.invalidResponse }

        return response.items
            .compactMap { dto -> Group? in
                let id = (dto.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let name = (dto.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, !name.isEmpty else { return nil }
                return Group(
                    id: id,
                    name: name,
                    fullName: (dto.field ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                    facultyId: facultyId
                )
            }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Календарь учебных недель (`/api/v1/timetable/weeks`).
    ///
    /// Новый API нумерует недели сам — веб-версия строит навигацию по нему,
    /// а не по календарным неделям.
    func fetchWeeks() async throws -> [ScheduleWeek] {
        let response: APIListEnvelope<ScheduleWeekDTO> = try await request(
            baseURL: primaryBaseURL,
            path: "/api/v1/timetable/weeks",
            queryItems: []
        )

        return response.items
            .enumerated()
            .compactMap { index, dto in dto.makeWeek(fallbackId: index + 1) }
            .sorted { $0.startDate < $1.startDate }
    }


    /// Получает расписание для конкретной группы.
    ///
    /// Эндпоинт общий для нового и старого формата, различается только payload:
    /// новый добавляет `day_layout_id`, `calendar_id`, `begins_at`/`ends_at`
    /// и подробности по группам. Разбор (см. `ScheduleItemDTO`) переваривает оба.
    ///
    /// - Parameters:
    ///   - groupName: известное имя группы. Если не передано — берём его из
    ///     `student_list`, но там перечислены все группы потока, поэтому
    ///     имя может оказаться чужим.
    ///   - weekNumber: номер учебной недели из `/timetable/weeks`, если он известен.
    func fetchSchedule(
        for groupId: String,
        startDate: Date = Date(),
        endDate: Date? = nil,
        groupName: String? = nil,
        weekNumber: Int? = nil
    ) async throws -> Schedule {
        let daysCount = Self.computeDaysCount(startDate: startDate, endDate: endDate)
        let startDateString = DateFormatter.serverDateFormatter.string(from: startDate)

        let response: APIListEnvelope<ScheduleItemDTO> = try await requestSchedule(
            groupId: groupId,
            daysCount: daysCount,
            startDateString: startDateString
        )

        // Группируем по дате
        var lessonsByDate: [Date: [Lesson]] = [:]
        var groupNameHits: [String: Int] = [:]

        for item in response.items {
            guard let lessonDate = item.lessonDate,
                  let timeStartHHmm = item.startHHmm else {
                continue
            }

            let lessonData = item.lessonData
            let timeEndHHmm = item.endHHmm ?? timeStartHHmm

            // Имя группы: считаем, какая встречается чаще всего — у потоковых пар
            // в `student_list` перечислены сразу несколько групп.
            let groups = (lessonData?.studentList ?? []).compactMap { $0.groupName }
            for name in groups {
                groupNameHits[name, default: 0] += 1
            }

            let typeName = lessonData?.courseType?.name
            let teachers = (lessonData?.teacherList ?? []).compactMap { dto -> Teacher? in
                guard let name = dto.displayName else { return nil }
                return Teacher(name: name, id: dto.id)
            }

            let lesson = Lesson(
                // Точный номер пары проставим ниже, когда увидим весь день целиком.
                pairNumber: ScheduleTimeFormat.bellPairNumber(forStartTime: timeStartHHmm) ?? 0,
                timeStart: timeStartHHmm,
                timeEnd: timeEndHHmm,
                type: LessonType(from: typeName ?? ""),
                subject: lessonData?.courseSubject?.name ?? typeName ?? "Занятие",
                room: Self.composeRoom(
                    name: lessonData?.studyPlace?.name,
                    ownerName: lessonData?.studyPlace?.ownerName
                ),
                teacher: teachers.first,
                groups: groups,
                onlineLink: nil,
                typeName: typeName,
                subjectAbbr: lessonData?.courseSubject?.nameAbbr,
                teachers: teachers.isEmpty ? nil : teachers
            )

            lessonsByDate[lessonDate, default: []].append(lesson)
        }

        let days: [ScheduleDay] = lessonsByDate
            .map { (date, lessons) in
                let weekday = DateFormatter.weekdayRuFormatter.string(from: date).capitalized
                return ScheduleDay(
                    date: date,
                    weekday: weekday,
                    weekNumber: weekNumber,
                    isEvenWeek: weekNumber.map { $0 % 2 == 0 },
                    lessons: Self.numberPairs(in: lessons)
                )
            }
            .sorted { $0.date < $1.date }

        let resolvedGroupName = groupName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? groupNameHits.max(by: { $0.value < $1.value })?.key

        return Schedule(
            groupId: groupId,
            groupName: resolvedGroupName ?? "Группа \(groupId)",
            startDate: startDate,
            endDate: endDate,
            days: days
        )
    }

    /// Имена query-параметров расписания.
    ///
    /// Сервер переехал с camelCase на snake_case и на старые имена отвечает
    /// 400 «schedule_type must be one of...». Держим оба варианта: сначала
    /// текущий, при 400 — прежний, чтобы приложение пережило и обратный
    /// переезд, и разные версии API у вуза и техникумов.
    private enum ScheduleParameterNaming: CaseIterable {
        case snakeCase
        case camelCase

        var scheduleType: String {
            switch self {
            case .snakeCase: return "schedule_type"
            case .camelCase: return "scheduleType"
            }
        }

        var startDate: String {
            switch self {
            case .snakeCase: return "start_date"
            case .camelCase: return "startDate"
            }
        }
    }

    private func requestSchedule(
        groupId: String,
        daysCount: Int,
        startDateString: String
    ) async throws -> APIListEnvelope<ScheduleItemDTO> {
        var lastError: Error?

        for naming in ScheduleParameterNaming.allCases {
            do {
                return try await request(
                    baseURL: primaryBaseURL,
                    path: "/api/v1/timetable/schedule",
                    queryItems: [
                        URLQueryItem(name: naming.scheduleType, value: "gr"),
                        URLQueryItem(name: "parameter", value: groupId),
                        URLQueryItem(name: "days", value: String(daysCount)),
                        URLQueryItem(name: naming.startDate, value: startDateString)
                    ]
                )
            } catch let error as APIError {
                // 400 — сервер не понял имена параметров, есть смысл пробовать
                // другой вариант. Всё остальное повторять бессмысленно.
                guard case .unexpectedStatus(let code, _) = error, code == 400 else { throw error }
                print("⚠️ Расписание: сервер не принял параметры \(naming), пробуем другой вариант")
                lastError = error
            }
        }

        throw lastError ?? APIError.invalidResponse
    }

    /// Сортирует пары дня по времени и проставляет номера.
    ///
    /// Сетка звонков вуза известна заранее, а у техникумов ассоциации она своя,
    /// поэтому для непопавших в сетку пар нумеруем по порядку внутри дня —
    /// раньше такие пары получали номер 0 и слипались при сортировке.
    private static func numberPairs(in lessons: [Lesson]) -> [Lesson] {
        let sorted = lessons.sorted { lhs, rhs in
            let lhsMinutes = ScheduleTimeFormat.minutesSinceMidnight(lhs.timeStart)
            let rhsMinutes = ScheduleTimeFormat.minutesSinceMidnight(rhs.timeStart)
            if lhsMinutes != rhsMinutes { return lhsMinutes < rhsMinutes }
            return lhs.subject.localizedCompare(rhs.subject) == .orderedAscending
        }

        // Пары в одно и то же время (подгруппы) должны получить один номер.
        var numbers: [Int: Int] = [:] // минуты начала -> номер пары
        var nextOrdinal = 0

        return sorted.map { lesson in
            let minutes = ScheduleTimeFormat.minutesSinceMidnight(lesson.timeStart)

            let number: Int
            if let known = numbers[minutes] {
                number = known
            } else {
                nextOrdinal += 1
                number = lesson.pairNumber > 0 ? lesson.pairNumber : nextOrdinal
                numbers[minutes] = number
            }
            nextOrdinal = max(nextOrdinal, number)

            guard number != lesson.pairNumber else { return lesson }

            return Lesson(
                pairNumber: number,
                timeStart: lesson.timeStart,
                timeEnd: lesson.timeEnd,
                type: lesson.type,
                subject: lesson.subject,
                room: lesson.room,
                teacher: lesson.teacher,
                groups: lesson.groups,
                onlineLink: lesson.onlineLink,
                isEvenWeek: lesson.isEvenWeek,
                typeName: lesson.typeName,
                subjectAbbr: lesson.subjectAbbr,
                teachers: lesson.teachers
            )
        }
    }


    /// Старые методы (HTML) удалены: новый API работает только через REST.
    func fetchScheduleByAuditorium(date: Date = Date()) async throws -> [ScheduleDay] {
        throw APIError.parseError("Метод не поддерживается новым API")
    }
    
    func fetchScheduleByTeacher(date: Date = Date()) async throws -> [ScheduleDay] {
        throw APIError.parseError("Метод не поддерживается новым API")
    }
    
    // MARK: - HTTP / JSON
    
    private struct APIEnvelope<T: Decodable>: Decodable {
        let status: String?
        let data: T
    }

    /// Конверт ответа со списком.
    ///
    /// Сервер отдаёт списки двумя способами:
    ///   старый — `{"status":"success","data":[ ... ]}`
    ///   новый  — `{"success":true,"data":{"items":[ ... ]}}`
    /// Разворачиваем оба, чтобы вызывающий код всегда получал массив.
    private struct APIListEnvelope<Element: Decodable>: Decodable {
        let items: [Element]

        private enum CodingKeys: String, CodingKey { case data }
        private enum DataKeys: String, CodingKey { case items }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)

            if let nested = try? container.nestedContainer(keyedBy: DataKeys.self, forKey: .data),
               let items = try? nested.decode([Element].self, forKey: .items) {
                self.items = items
                return
            }

            items = try container.decode([Element].self, forKey: .data)
        }
    }
    
    private func requestData(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> Data {
        do {
            return try await performRequestData(baseURL: baseURL, path: path, queryItems: queryItems)
        } catch {
            guard shouldFallback(from: error),
                  fallbackBaseURL.host != baseURL.host else { throw error }
            return try await performRequestData(baseURL: fallbackBaseURL, path: path, queryItems: queryItems)
        }
    }
    
    private func request<T: Decodable>(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> T {
        // Пробуем primary, при нужных ошибках — fallback.
        do {
            return try await performRequest(baseURL: baseURL, path: path, queryItems: queryItems)
        } catch {
            guard shouldFallback(from: error),
                  fallbackBaseURL.host != baseURL.host else { throw error }
            return try await performRequest(baseURL: fallbackBaseURL, path: path, queryItems: queryItems)
        }
    }
    
    private func performRequest<T: Decodable>(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> T {
        let data = try await performRequestData(baseURL: baseURL, path: path, queryItems: queryItems)
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            let preview = String(data: data, encoding: .utf8) ?? ""
            throw APIError.parseError("\(error.localizedDescription). Response preview: \(preview.prefix(300))")
        }
    }
    
    private func performRequestData(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> Data {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let endpointURL = baseURL.appendingPathComponent(cleanPath)
        
        guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        
        guard let url = components.url else { throw APIError.invalidURL }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        applyDefaultHeaders(to: &request, baseURL: baseURL, path: path)
        request.timeoutInterval = requestTimeoutSeconds
        
        do {
            let (data, httpResponse) = try await performRequestHandlingAuthorization(request)
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.unexpectedStatus(code: httpResponse.statusCode, path: path)
            }
            
            if let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               text == "{}" || text.isEmpty {
                throw APIError.emptyResponse
            }
            
            return data
        } catch let apiError as APIError {
            throw apiError
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    throw APIError.requestTimedOut(seconds: Int(requestTimeoutSeconds))
                case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
                    throw APIError.vpnOrBlockedNetwork
                default:
                    break
                }
            }
            throw APIError.networkError(error)
        }
    }

    private func performRequestHandlingAuthorization(
        _ request: URLRequest,
        allowReauthorization: Bool = true
    ) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if isAuthorizationFailure(statusCode: httpResponse.statusCode) {
            print("🔐 DVGUPS API: got \(httpResponse.statusCode) for \(request.url?.absoluteString ?? "<nil>")")
            if allowReauthorization {
                do {
                    print("🔐 DVGUPS API: trying silent reauth")
                    try await authService.reauthorizeIfPossible()
                    print("🔐 DVGUPS API: silent reauth succeeded, retrying request")
                } catch let apiError as APIError {
                    if case .authenticationRequired = apiError {
                        authService.markAuthorizationRequired()
                    }
                    print("🔐 DVGUPS API: silent reauth failed: \(apiError.localizedDescription)")
                    throw apiError
                }

                return try await performRequestHandlingAuthorization(request, allowReauthorization: false)
            }

            if authService.status.isAuthenticated {
                throw APIError.invalidCredentials
            }

            throw APIError.authenticationRequired
        }

        if isProtectedTimetablePath(request.url), (200...299).contains(httpResponse.statusCode) {
            authService.noteProtectedRequestSucceeded()
        }

        return (data, httpResponse)
    }

    private func applyDefaultHeaders(to request: inout URLRequest, baseURL: URL, path: String) {
        request.setValue(DVGUPSBrowserProfile.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(DVGUPSBrowserProfile.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        // `Connection` намеренно не ставим: в HTTP/2 этот заголовок запрещён
        // (RFC 9113, 8.2.2), веб-версия его не шлёт, а соединениями и так
        // управляет URLSession.

        guard baseURL.host == primaryBaseURL.host, path.hasPrefix("/api/v1/") else {
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            return
        }

        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("u=3, i", forHTTPHeaderField: "Priority")
        request.setValue(referer(for: path), forHTTPHeaderField: "Referer")
    }

    private func isAuthorizationFailure(statusCode: Int) -> Bool {
        statusCode == 401 || statusCode == 403
    }

    private func isProtectedTimetablePath(_ url: URL?) -> Bool {
        guard let path = url?.path else { return false }
        return path.contains("/api/v1/timetable/")
    }

    private func referer(for path: String) -> String {
        if path.contains("/api/v1/timetable/weeks") || path.contains("/api/v1/timetable/schedule") {
            return "https://dvgups.ru/public/schedule/group"
        }

        if path.contains("/api/v1/timetable/") {
            return "https://dvgups.ru/public/schedule"
        }

        return "https://dvgups.ru/"
    }
    
    private func shouldFallback(from error: Error) -> Bool {
        // Если проблема именно в недоступности next, идём на обычный домен.
        // vpnOrBlockedNetwork может быть и для обычного домена, но по ТЗ fallback нужен именно когда next недоступен.
        if let apiError = error as? APIError {
            switch apiError {
            case .vpnOrBlockedNetwork:
                return true
            case .requestTimedOut:
                return true
            case .emptyResponse:
                return true
            case .invalidResponse:
                return true
            case .unexpectedStatus(let code, _):
                // Повторяем только серверные сбои: 404 и 400 от повтора не исправятся.
                return (500...599).contains(code)
            default:
                return false
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        return false
    }
    
    // MARK: - Helpers
    
    private static func computeDaysCount(startDate: Date, endDate: Date?) -> Int {
        guard let endDate else { return 7 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let components = calendar.dateComponents([.day], from: start, to: end)
        let diff = (components.day ?? 0)
        // В API параметр days обычно включает startDate как "день 1"
        return max(1, diff + 1)
    }
    
    private static func composeRoom(name: String?, ownerName: String?) -> String? {
        // Новый API присылает аудиторию с двойными пробелами ("а.  418") — схлопываем.
        guard let trimmedName = name?.collapsingWhitespace(), !trimmedName.isEmpty else { return nil }

        if let owner = ownerName?.collapsingWhitespace(), !owner.isEmpty {
            return "\(trimmedName) • \(owner)"
        }
        return trimmedName
    }
}

// MARK: - String helpers

extension String {
    /// `nil` вместо пустой строки — удобно в цепочках `??`.
    var nilIfEmpty: String? { isEmpty ? nil : self }

    /// Схлопывает повторяющиеся пробелы и обрезает края.
    func collapsingWhitespace() -> String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

// MARK: - DateFormatter Extension

extension DateFormatter {
    /// Форматтер для парсинга дат из API (например, "01.09.2025")
    static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return formatter
    }()
    
    /// Форматтер для отображения дат пользователю
    static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy, EEEE"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return formatter
    }()
    
    /// Форматтер для отображения времени
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return formatter
    }()
    
    /// Форматтер даты для нового REST API (например, "2026-02-09")
    static let serverDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return formatter
    }()
    
    /// Форматтер для дня недели на русском (например, "понедельник")
    static let weekdayRuFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return formatter
    }()
}

// MARK: - Новости ДВГУПС

/// API клиент для загрузки новостей ДВГУПС
@MainActor
class DVGUPSNewsAPIClient: ObservableObject {
    private let baseURL = "https://www.dvgups.ru/news.php"
    private let session: URLSession
    private let itemsPerPage = 10
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    /// Загружает новости с поддержкой пагинации
    func fetchNews(offset: Int = 0) async throws -> NewsResponse {
        guard let url = URL(string: "\(baseURL)?st=\(offset)") else {
            throw NewsError.invalidURL
        }
        
        print("🌐 NewsAPIClient.fetchNews() - Offset: \(offset)")
        
        var request = URLRequest(url: url)
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("www.dvgups.ru", forHTTPHeaderField: "Host")
        request.timeoutInterval = 30
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw NewsError.networkError(URLError(.badServerResponse))
            }
            
            guard let xmlString = String(data: data, encoding: .utf8) else {
                throw NewsError.noData
            }
            
            let newsItems = try parseNewsXML(xmlString)
            // Более умная проверка пагинации
            let hasMorePages = newsItems.count == itemsPerPage && !newsItems.isEmpty
            let nextOffset = offset + newsItems.count
            
            print("✅ Loaded \(newsItems.count) news items, hasMore: \(hasMorePages)")
            
            return NewsResponse(items: newsItems, hasMorePages: hasMorePages, nextOffset: nextOffset)
            
        } catch {
            print("❌ Error loading news: \(error)")
            throw NewsError.networkError(error)
        }
    }
    
    /// Парсит XML ответ с новостями в RSS формате
    private func parseNewsXML(_ xml: String) throws -> [NewsItem] {
        var newsItems: [NewsItem] = []
        
        // Регулярные выражения для извлечения данных из XML
        let itemPattern = #"<item>(.*?)</item>"#
        let idPattern = #"<id>(\d+)</id>"#
        let titlePattern = #"<title>(.*?)</title>"#
        let descriptionPattern = #"<description>(.*?)</description>"#
        let fullPattern = #"<full>(.*?)</full>"#
        let imagePattern = #"<imageur><img>(.*?)</img></imageur>"#
        let datePattern = #"<date>(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})</date>"#
        let hitsPattern = #"<hits>(\d+)</hits>"#
        
        let itemRegex = try NSRegularExpression(pattern: itemPattern, options: [.dotMatchesLineSeparators])
        let nsString = xml as NSString
        let matches = itemRegex.matches(in: xml, options: [], range: NSRange(location: 0, length: nsString.length))
        
        for match in matches {
            guard match.numberOfRanges > 1 else { continue }
            
            let itemContent = nsString.substring(with: match.range(at: 1))
            
            // Извлекаем данные из каждого элемента
            let id = extractValue(from: itemContent, pattern: idPattern) ?? UUID().uuidString
            let title = extractValue(from: itemContent, pattern: titlePattern)?.decodingHTMLEntities() ?? ""
            let description = extractValue(from: itemContent, pattern: descriptionPattern)?.decodingHTMLEntities() ?? ""
            let fullText = extractValue(from: itemContent, pattern: fullPattern)?.decodingHTMLEntities() ?? ""
            let imageURL = extractValue(from: itemContent, pattern: imagePattern)
            let dateString = extractValue(from: itemContent, pattern: datePattern) ?? ""
            let hitsString = extractValue(from: itemContent, pattern: hitsPattern) ?? "0"
            
            // Парсим дату
            let date = NewsItem.newsDateFormatter.date(from: dateString) ?? Date()
            let hits = Int(hitsString) ?? 0
            
            let newsItem = NewsItem(
                id: id,
                title: title,
                description: description,
                fullText: fullText,
                imageURL: imageURL,
                date: date,
                hits: hits
            )
            
            newsItems.append(newsItem)
        }
        
        return newsItems
    }
    
    /// Извлекает значение по регулярному выражению
    private func extractValue(from text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            return nil
        }
        
        let nsString = text as NSString
        let results = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
        
        guard let match = results.first, match.numberOfRanges > 1 else {
            return nil
        }
        
        return nsString.substring(with: match.range(at: 1))
    }
}

// MARK: - HTML Entities Extension

extension String {
    /// Декодирует HTML entities
    func decodingHTMLEntities() -> String {
        return self
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
