import Foundation

/// Ошибки API клиента
enum APIError: Error, LocalizedError {
    case invalidURL
    case noData
    case parseError(String)
    case networkError(Error)
    case invalidResponse
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
    private let requestTimeoutSeconds: TimeInterval = 8
    
    // MARK: - Инициализация
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    // MARK: - Публичные методы (REST)
    
    struct FacultiesResult {
        let faculties: [Faculty]
        /// Названия институтов/факультетов, которые пришли без ID (их нельзя выбрать/использовать для запроса групп)
        let missingIdNames: [String]
    }
    
    /// Получает список институтов/факультетов (динамически)
    func fetchFaculties() async throws -> FacultiesResult {
        // ВУЗ иногда меняет формат отдачи: встречались как "табличка" [[id, name]],
        // так и нормальный массив объектов. Декодим в 2 прохода.
        let data = try await requestData(
            baseURL: primaryBaseURL,
            path: "/api/v1/timetable/faculties",
            queryItems: []
        )
        
        var faculties: [Faculty] = []
        var missingIdNames: [String] = []
        
        // Формат 1: data = [[id?, name?], ...]
        if let envelope = try? JSONDecoder().decode(APIEnvelope<[[String?]]>.self, from: data) {
            for row in envelope.data {
                let rawId = row.count > 0 ? row[0] : nil
                let name = row.count > 1 ? row[1] : nil
                
                guard let facultyName = name?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !facultyName.isEmpty else { continue }
                
                guard let id = rawId?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !id.isEmpty else {
                    // По ТЗ: не подставляем id из старого списка. Просто сообщаем в UI.
                    missingIdNames.append(facultyName)
                    continue
                }
                
                faculties.append(Faculty(id: id, name: facultyName))
            }
        } else {
            // Формат 2: data = [{ id, name }, ...] (оборачивается в status/data)
            struct FacultyDTO: Decodable {
                let id: String?
                let name: String?
            }
            let envelope = try JSONDecoder().decode(APIEnvelope<[FacultyDTO]>.self, from: data)
            for dto in envelope.data {
                let facultyName = (dto.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !facultyName.isEmpty else { continue }
                
                let id = (dto.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty else {
                    missingIdNames.append(facultyName)
                    continue
                }
                
                faculties.append(Faculty(id: id, name: facultyName))
            }
        }
        
        // Убираем дубликаты по id, сортируем по названию
        let unique = Dictionary(grouping: faculties, by: { $0.id })
            .compactMap { $0.value.first }
            .sorted { $0.name < $1.name }
        
        return FacultiesResult(
            faculties: unique,
            missingIdNames: Array(Set(missingIdNames)).sorted()
        )
    }
    
    /// Получает список групп для выбранного факультета/института
    func fetchGroups(for facultyId: String) async throws -> [Group] {
        struct GroupDTO: Decodable {
            let id: String
            let name: String
            let field: String
        }
        
        let response: APIEnvelope<[GroupDTO]> = try await request(
            baseURL: primaryBaseURL,
            path: "/api/v1/timetable/groups/by-faculty",
            queryItems: [
                URLQueryItem(name: "facultyId", value: facultyId)
            ]
        )
        
        return response.data
            .map { Group(id: $0.id, name: $0.name, fullName: $0.field, facultyId: facultyId) }
            .sorted { $0.name < $1.name }
    }
    
    /// Получает расписание для конкретной группы
    func fetchSchedule(for groupId: String, startDate: Date = Date(), endDate: Date? = nil) async throws -> Schedule {
        let daysCount = Self.computeDaysCount(startDate: startDate, endDate: endDate)
        let startDateString = DateFormatter.serverDateFormatter.string(from: startDate)
        
        struct ScheduleItemDTO: Decodable {
            let startTime: String
            let endTime: String
            let date: String
            let lessonData: LessonDataDTO
            
            struct LessonDataDTO: Decodable {
                let courseType: CourseTypeDTO
                let courseSubject: CourseSubjectDTO
                let teacherList: [TeacherDTO]
                let studentList: [StudentDTO]
                let studyPlace: StudyPlaceDTO?
                
                struct CourseTypeDTO: Decodable { let name: String; let nameAbbr: String?
                    enum CodingKeys: String, CodingKey { case name; case nameAbbr = "name_abbr" }
                }
                struct CourseSubjectDTO: Decodable { let name: String; let nameAbbr: String?
                    enum CodingKeys: String, CodingKey { case name; case nameAbbr = "name_abbr" }
                }
                struct TeacherDTO: Decodable { let name: String; let nameAbbr: String?
                    enum CodingKeys: String, CodingKey { case name; case nameAbbr = "name_abbr" }
                }
                struct StudentDTO: Decodable {
                    let name: String?
                    let nameAbbr: String?
                    let studentGroupName: String?
                    let studentGroupNameAbbr: String?
                    let facultyName: String?
                    let facultyNameAbbr: String?
                    
                    enum CodingKeys: String, CodingKey {
                        case name
                        case nameAbbr = "name_abbr"
                        case studentGroupName = "student_group_name"
                        case studentGroupNameAbbr = "student_group_name_abbr"
                        case facultyName = "faculty_name"
                        case facultyNameAbbr = "faculty_name_abbr"
                    }
                }
                struct StudyPlaceDTO: Decodable {
                    let name: String
                    let ownerName: String?
                    enum CodingKeys: String, CodingKey { case name; case ownerName = "owner_name" }
                }
                
                enum CodingKeys: String, CodingKey {
                    case courseType = "course_type"
                    case courseSubject = "course_subject"
                    case teacherList = "teacher_list"
                    case studentList = "student_list"
                    case studyPlace = "study_place"
                }
            }
            
            enum CodingKeys: String, CodingKey {
                case startTime = "start_time"
                case endTime = "end_time"
                case date
                case lessonData = "lesson_data"
            }
        }
        
        let response: APIEnvelope<[ScheduleItemDTO]> = try await request(
            baseURL: primaryBaseURL,
            path: "/api/v1/timetable/schedule",
            queryItems: [
                URLQueryItem(name: "scheduleType", value: "gr"),
                URLQueryItem(name: "parameter", value: groupId),
                URLQueryItem(name: "days", value: String(daysCount)),
                URLQueryItem(name: "startDate", value: startDateString)
            ]
        )
        
        // Группируем по дате
        var lessonsByDate: [Date: [Lesson]] = [:]
        var resolvedGroupName: String? = nil
        
        for item in response.data {
            guard let lessonDate = DateFormatter.serverDateFormatter.date(from: item.date) else {
                continue
            }
            
            // Пытаемся вытащить имя группы из student_list
            if resolvedGroupName == nil {
                resolvedGroupName =
                    item.lessonData.studentList.first?.studentGroupNameAbbr ??
                    item.lessonData.studentList.first?.studentGroupName ??
                    item.lessonData.studentList.first?.nameAbbr ??
                    item.lessonData.studentList.first?.name
            }
            
            let timeStartHHmm = Self.hhmm(fromHHmmss: item.startTime)
            let timeEndHHmm = Self.hhmm(fromHHmmss: item.endTime)
            
            let pairNumber = Self.pairNumber(forStartTime: timeStartHHmm)
            
            let lessonType = LessonType(from: item.lessonData.courseType.name)
            let subject = item.lessonData.courseSubject.name
            
            let room = Self.composeRoom(
                name: item.lessonData.studyPlace?.name,
                ownerName: item.lessonData.studyPlace?.ownerName
            )
            
            let teacherName = item.lessonData.teacherList.first?.nameAbbr ?? item.lessonData.teacherList.first?.name
            let teacher: Teacher? = (teacherName?.isEmpty == false) ? Teacher(name: teacherName!) : nil
            
            let groups = item.lessonData.studentList.compactMap { $0.studentGroupNameAbbr ?? $0.studentGroupName ?? $0.nameAbbr }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            
            let lesson = Lesson(
                pairNumber: pairNumber,
                timeStart: timeStartHHmm,
                timeEnd: timeEndHHmm,
                type: lessonType,
                subject: subject,
                room: room,
                teacher: teacher,
                groups: groups,
                onlineLink: nil
            )
            
            lessonsByDate[lessonDate, default: []].append(lesson)
        }
        
        let days: [ScheduleDay] = lessonsByDate
            .map { (date, lessons) in
                let weekday = DateFormatter.weekdayRuFormatter.string(from: date).capitalized
                return ScheduleDay(
                    date: date,
                    weekday: weekday,
                    weekNumber: nil,
                    isEvenWeek: nil,
                    lessons: lessons.sorted { lhs, rhs in
                        if lhs.pairNumber != rhs.pairNumber { return lhs.pairNumber < rhs.pairNumber }
                        return lhs.timeStart < rhs.timeStart
                    }
                )
            }
            .sorted { $0.date < $1.date }
        
        return Schedule(
            groupId: groupId,
            groupName: resolvedGroupName ?? "Группа \(groupId)",
            startDate: startDate,
            endDate: endDate,
            days: days
        )
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
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = requestTimeoutSeconds
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            // Если запасной домен отвечает 5xx — пробуем fallback/ошибку отдать наверх через общий retry.
            if (500...599).contains(httpResponse.statusCode), baseURL == primaryBaseURL {
                throw APIError.invalidResponse
            }
            
            guard (200...299).contains(httpResponse.statusCode) else {
                throw APIError.invalidResponse
            }
            
            if let text = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               text == "{}" || text.isEmpty {
                throw APIError.emptyResponse
            }
            
            return data
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
    
    private static func hhmm(fromHHmmss value: String) -> String {
        // "16:55:00" -> "16:55"
        if value.count >= 5 {
            return String(value.prefix(5))
        }
        return value
    }
    
    private static func pairNumber(forStartTime hhmm: String) -> Int {
        func parse(_ s: String) -> (Int, Int)? {
            let parts = s.split(separator: ":")
            guard parts.count >= 2,
                  let h = Int(parts[0]),
                  let m = Int(parts[1]) else { return nil }
            return (h, m)
        }
        
        guard let target = parse(hhmm) else { return 0 }
        
        for t in LessonTime.schedule {
            if let start = parse(t.startTime), start == target {
                return t.number
            }
        }
        
        // Фолбек: "08:05" vs "8:05" и наоборот
        if hhmm.hasPrefix("0"), let alt = parse(String(hhmm.dropFirst())) {
            for t in LessonTime.schedule {
                if let start = parse(t.startTime), start == alt {
                    return t.number
                }
            }
        }
        
        return 0
    }
    
    private static func composeRoom(name: String?, ownerName: String?) -> String? {
        guard let name else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = ownerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let owner, !owner.isEmpty {
            return "\(trimmedName) • \(owner)"
        }
        return trimmedName.isEmpty ? nil : trimmedName
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