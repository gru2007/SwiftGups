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
            return "Не удалось подключиться к серверу. Возможно включен VPN или сеть блокирует доступ к dvgups.ru. Отключите VPN/смените сервер и повторите попытку."
        }
    }
}

/// API клиент для работы с расписанием ДВГУПС
@MainActor
class DVGUPSAPIClient: ObservableObject {
    
    // MARK: - Константы
    
    private let baseURL = "https://dvgups.ru/index.php"
    private let itemId = "1246"
    private let option = "com_timetable"
    private let view = "newtimetable"
    
    private let session: URLSession
    
    // MARK: - Инициализация
    
    init(session: URLSession = .shared) {
        self.session = session
    }
    
    // MARK: - Публичные методы
    
    /// Получает список групп для выбранного факультета
    func fetchGroups(for facultyId: String, date: Date = Date()) async throws -> [Group] {
        let dateString = DateFormatter.apiDateFormatter.string(from: date)
        let requestBody = "FacID=\(facultyId)&GroupID=no&Time=\(dateString)"
        
        print("🌐 APIClient.fetchGroups() - Faculty: \(facultyId), Date: \(dateString)")
        print("📤 Request body: \(requestBody)")
        
        let htmlResponse = try await performRequest(body: requestBody)
        let groups = parseGroups(from: htmlResponse, facultyId: facultyId)
        
        print("🔍 Parsed \(groups.count) groups from response")
        if groups.isEmpty {
            print("⚠️ No groups found in HTML response for faculty \(facultyId)")
            // Логируем часть HTML для отладки
            let preview = String(htmlResponse.prefix(500))
            print("📄 HTML preview: \(preview)")
        }
        
        return groups
    }
    
    /// Получает расписание для конкретной группы
    func fetchSchedule(for groupId: String, startDate: Date = Date(), endDate: Date? = nil) async throws -> Schedule {
        let dateString = DateFormatter.apiDateFormatter.string(from: startDate)
        let requestBody = "GroupID=\(groupId)&Time=\(dateString)"
        
        let htmlResponse = try await performRequest(body: requestBody)
        return try parseSchedule(from: htmlResponse, groupId: groupId, startDate: startDate, endDate: endDate)
    }
    
    /// Получает расписание по аудиториям для выбранной даты
    func fetchScheduleByAuditorium(date: Date = Date()) async throws -> [ScheduleDay] {
        let dateString = DateFormatter.apiDateFormatter.string(from: date)
        let requestBody = "AudID=no&Time=\(dateString)"
        
        let htmlResponse = try await performRequest(body: requestBody)
        return parseScheduleDays(from: htmlResponse)
    }
    
    /// Получает расписание по преподавателям для выбранной даты
    func fetchScheduleByTeacher(date: Date = Date()) async throws -> [ScheduleDay] {
        let dateString = DateFormatter.apiDateFormatter.string(from: date)
        let requestBody = "PrepID=no&Time=\(dateString)"
        
        let htmlResponse = try await performRequest(body: requestBody)
        return parseScheduleDays(from: htmlResponse)
    }
    
    // MARK: - Приватные методы
    
    /// Создает базовый URL для API запросов
    private func createBaseURL() -> URL? {
        var components = URLComponents(string: baseURL)
        components?.queryItems = [
            URLQueryItem(name: "Itemid", value: itemId),
            URLQueryItem(name: "option", value: option),
            URLQueryItem(name: "view", value: view)
        ]
        return components?.url
    }
    
    /// Выполняет HTTP POST запрос к API
    private func performRequest(body: String) async throws -> String {
        guard let url = createBaseURL() else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("XMLHttpRequest", forHTTPHeaderField: "X-Requested-With")
        request.httpBody = body.data(using: .utf8)
        request.timeoutInterval = 20
        
        do {
            let (data, response) = try await session.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                throw APIError.invalidResponse
            }
            
            guard let htmlString = String(data: data, encoding: .utf8) else {
                throw APIError.noData
            }
            
            return htmlString
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut, .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
                    // Часто возникает при активном VPN/блокировке
                    throw APIError.vpnOrBlockedNetwork
                default:
                    break
                }
            }
            throw APIError.networkError(error)
        }
    }
    
    // MARK: - Парсинг HTML
    
    /// Парсит список групп из HTML ответа
    private func parseGroups(from html: String, facultyId: String) -> [Group] {
        var groups: [Group] = []
        
        // Ищем все option теги с группами
        let optionPattern = #"<option value='(\d+)'>гр\.\s*([^-]+)\s*-\s*([^<]+)</option>"#
        let regex = try? NSRegularExpression(pattern: optionPattern, options: [])
        let nsString = html as NSString
        let results = regex?.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        print("🔍 Found \(results.count) regex matches for groups pattern")
        
        if results.isEmpty {
            // Попробуем найти любые option теги для отладки
            let anyOptionPattern = #"<option[^>]*>(.*?)</option>"#
            let debugRegex = try? NSRegularExpression(pattern: anyOptionPattern, options: [])
            let debugResults = debugRegex?.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
            print("🐛 Found \(debugResults.count) total option tags in response")
            
            // Показываем первые несколько option тегов для отладки
            for (index, match) in debugResults.prefix(5).enumerated() {
                if match.numberOfRanges > 0 {
                    let matchRange = match.range(at: 0)
                    let matchText = nsString.substring(with: matchRange)
                    print("🐛 Option \(index + 1): \(matchText)")
                }
            }
        }
        
        for result in results {
            guard result.numberOfRanges == 4 else { continue }
            
            let groupIdRange = result.range(at: 1)
            let groupNameRange = result.range(at: 2)
            let fullNameRange = result.range(at: 3)
            
            guard groupIdRange.location != NSNotFound,
                  groupNameRange.location != NSNotFound,
                  fullNameRange.location != NSNotFound else { continue }
            
            let groupId = nsString.substring(with: groupIdRange)
            let groupName = nsString.substring(with: groupNameRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let fullName = nsString.substring(with: fullNameRange).trimmingCharacters(in: .whitespacesAndNewlines)
            
            let group = Group(id: groupId, name: groupName, fullName: fullName, facultyId: facultyId)
            groups.append(group)
            print("✅ Parsed group: \(groupName) (ID: \(groupId))")
        }
        
        return groups.sorted { $0.name < $1.name }
    }
    
    /// Парсит расписание из HTML ответа
    private func parseSchedule(from html: String, groupId: String, startDate: Date, endDate: Date?) throws -> Schedule {
        let days = parseScheduleDays(from: html)
        
        // Получаем название группы из HTML (если возможно)
        let groupName = extractGroupName(from: html) ?? "Группа \(groupId)"
        
        return Schedule(
            groupId: groupId,
            groupName: groupName,
            startDate: startDate,
            endDate: endDate,
            days: days
        )
    }
    
    /// Парсит дни расписания из HTML ответа
    private func parseScheduleDays(from html: String) -> [ScheduleDay] {
        var days: [ScheduleDay] = []
        
        // Парсим заголовки дней (например: "01.09.2025 Понедельник (2-я неделя)")
        let dayHeaderPattern = #"<h3>(\d{2}\.\d{2}\.\d{4})\s+([А-Я][а-я]+)\s+\((\d+)-я неделя\)</h3>"#
        let dayRegex = try? NSRegularExpression(pattern: dayHeaderPattern, options: [])
        
        // Парсим таблицы с занятиями
        let tablePattern = #"<h3>.*?</h3><table.*?>(.*?)</table>"#
        let tableRegex = try? NSRegularExpression(pattern: tablePattern, options: [.dotMatchesLineSeparators])
        
        let nsString = html as NSString
        let dayMatches = dayRegex?.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        let tableMatches = tableRegex?.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        guard dayMatches.count == tableMatches.count else {
            return days
        }
        
        for (index, dayMatch) in dayMatches.enumerated() {
            guard dayMatch.numberOfRanges == 4,
                  index < tableMatches.count else { continue }
            
            let dateRange = dayMatch.range(at: 1)
            let weekdayRange = dayMatch.range(at: 2)
            let weekNumberRange = dayMatch.range(at: 3)
            let tableContentRange = tableMatches[index].range(at: 1)
            
            guard dateRange.location != NSNotFound,
                  weekdayRange.location != NSNotFound,
                  weekNumberRange.location != NSNotFound,
                  tableContentRange.location != NSNotFound else { continue }
            
            let dateString = nsString.substring(with: dateRange)
            let weekdayString = nsString.substring(with: weekdayRange)
            let weekNumberString = nsString.substring(with: weekNumberRange)
            let tableContent = nsString.substring(with: tableContentRange)
            
            guard let date = DateFormatter.apiDateFormatter.date(from: dateString),
                  let weekNumber = Int(weekNumberString) else { continue }
            
            let lessons = parseLessons(from: tableContent)
            let isEvenWeek = weekNumber % 2 == 0
            
            let scheduleDay = ScheduleDay(
                date: date,
                weekday: weekdayString,
                weekNumber: weekNumber,
                isEvenWeek: isEvenWeek,
                lessons: lessons
            )
            
            days.append(scheduleDay)
        }
        
        return days.sorted { $0.date < $1.date }
    }
    
    /// Парсит занятия из HTML таблицы
    private func parseLessons(from tableHtml: String) -> [Lesson] {
        var lessons: [Lesson] = []
        
        // Упрощенный паттерн для парсинга строк таблицы
        let rowPattern = #"<tr[^>]*>(.*?)</tr>"#
        let rowRegex = try? NSRegularExpression(pattern: rowPattern, options: [.dotMatchesLineSeparators])
        let nsString = tableHtml as NSString
        let rowResults = rowRegex?.matches(in: tableHtml, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        for rowResult in rowResults {
            let rowContent = nsString.substring(with: rowResult.range(at: 1))
            
            // Парсим отдельные компоненты урока
            if let lesson = parseIndividualLesson(from: rowContent) {
                lessons.append(lesson)
            }
        }
        
        return lessons.sorted { $0.pairNumber < $1.pairNumber }
    }
    
    /// Парсит отдельный урок из HTML строки таблицы
    private func parseIndividualLesson(from rowContent: String) -> Lesson? {
        // Парсим номер пары
        let pairNumberPattern = #"<b[^>]*>\s*(\d+)-я пара\s*</b>"#
        let pairNumberRegex = try? NSRegularExpression(pattern: pairNumberPattern)
        let pairNumberMatch = pairNumberRegex?.firstMatch(in: rowContent, range: NSRange(location: 0, length: rowContent.count))
        
        guard let pairMatch = pairNumberMatch,
              let pairRange = Range(pairMatch.range(at: 1), in: rowContent) else {
            return nil
        }
        
        let pairNumber = Int(String(rowContent[pairRange])) ?? 0
        
        // Парсим время
        let timePattern = #"(\d{2}:\d{2}-\d{2}:\d{2})"#
        let timeRegex = try? NSRegularExpression(pattern: timePattern)
        let timeMatch = timeRegex?.firstMatch(in: rowContent, range: NSRange(location: 0, length: rowContent.count))
        
        guard let timeMatchResult = timeMatch,
              let timeRange = Range(timeMatchResult.range(at: 1), in: rowContent) else {
            return nil
        }
        
        let timeString = String(rowContent[timeRange])
        let timeComponents = timeString.split(separator: "-")
        guard timeComponents.count == 2 else { return nil }
        
        // Парсим предмет и тип занятия
        let subjectPattern = #"<div>\(([^)]+)\)\s*([^<]+)</div>"#
        let subjectRegex = try? NSRegularExpression(pattern: subjectPattern)
        let subjectMatch = subjectRegex?.firstMatch(in: rowContent, range: NSRange(location: 0, length: rowContent.count))
        
        var lessonType = LessonType.lecture
        var subject = ""
        
        if let subjectMatchResult = subjectMatch,
           let typeRange = Range(subjectMatchResult.range(at: 1), in: rowContent),
           let subjRange = Range(subjectMatchResult.range(at: 2), in: rowContent) {
            lessonType = LessonType(from: String(rowContent[typeRange]))
            subject = String(rowContent[subjRange]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        // Парсим дополнительную информацию (ZOOM, Discord, etc.)
        let additionalInfoPattern = #"<div>([^<]*(?:ZOOM|Discord|FreeConferenceCall|код доступа|Идентификатор)[^<]*)</div>"#
        let additionalInfoRegex = try? NSRegularExpression(pattern: additionalInfoPattern, options: [.caseInsensitive])
        let additionalInfoMatch = additionalInfoRegex?.firstMatch(in: rowContent, range: NSRange(location: 0, length: rowContent.count))
        
        var onlineInfo: String? = nil
        if let additionalInfoMatchResult = additionalInfoMatch,
           let infoRange = Range(additionalInfoMatchResult.range(at: 1), in: rowContent) {
            let info = String(rowContent[infoRange])
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\n", with: " ")
            if !info.isEmpty {
                onlineInfo = info
            }
        }
        
        // Парсим аудиторию - ищем в td с wrap
        let auditoriumPattern = #"<td[^>]*wrap[^>]*>([^<]*)</td>"#
        let auditoriumRegex = try? NSRegularExpression(pattern: auditoriumPattern)
        let auditoriumMatch = auditoriumRegex?.firstMatch(in: rowContent, range: NSRange(location: 0, length: rowContent.count))
        
        var auditorium: String? = nil
        if let auditoriumMatchResult = auditoriumMatch,
           let audRange = Range(auditoriumMatchResult.range(at: 1), in: rowContent) {
            let aud = String(rowContent[audRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !aud.isEmpty && aud != " " {
                auditorium = aud
            }
        }
        
        // Парсим преподавателя
        let teacherPattern = #"<div>([^<]+?)(?:\s*<a[^>]*href='mailto:([^']+)'[^>]*>&#9993;</a>)?</div>"#
        let teacherRegex = try? NSRegularExpression(pattern: teacherPattern)
        
        var teacher: Teacher? = nil
        let teacherMatches = teacherRegex?.matches(in: rowContent, options: [], range: NSRange(location: 0, length: rowContent.count)) ?? []
        
        // Берем последний матч - обычно это преподаватель
        if let lastTeacherMatch = teacherMatches.last,
           let nameRange = Range(lastTeacherMatch.range(at: 1), in: rowContent) {
            let teacherName = String(rowContent[nameRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            
            // Проверяем что это не пустое поле и не другие данные
            if !teacherName.isEmpty && 
               teacherName != " " && 
               !teacherName.contains("wrap") &&
               !teacherName.contains("БО2") { // исключаем названия групп
                
                var teacherEmail: String? = nil
                if lastTeacherMatch.numberOfRanges > 2,
                   let emailRange = Range(lastTeacherMatch.range(at: 2), in: rowContent) {
                    let email = String(rowContent[emailRange]).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !email.isEmpty {
                        teacherEmail = email
                    }
                }
                
                teacher = Teacher(name: teacherName, email: teacherEmail)
            }
        }
        
        return Lesson(
            pairNumber: pairNumber,
            timeStart: String(timeComponents[0]),
            timeEnd: String(timeComponents[1]),
            type: lessonType,
            subject: subject,
            room: auditorium,
            teacher: teacher,
            groups: [],
            onlineLink: onlineInfo
        )
    }
    
    // Оригинальная функция как fallback
    private func parseLessonsOriginal(from tableHtml: String) -> [Lesson] {
        var lessons: [Lesson] = []
        
        // Паттерн для парсинга строк таблицы с занятиями
        let lessonPattern = #"<tr[^>]*>.*?<b[^>]*>\s*(\d+)-я пара\s*</b>.*?(\d{2}:\d{2}-\d{2}:\d{2}).*?<div>\(([^)]+)\)\s*([^<]+)</div>.*?<div>([^<]*)</div>.*?wrap>([^<]*)</td>.*?>([^<]*)</td>.*?<div>([^<]*?)(?:<a[^>]*href='mailto:([^']*)'[^>]*>&#9993;</a>)?</div>"#
        
        let regex = try? NSRegularExpression(pattern: lessonPattern, options: [.dotMatchesLineSeparators])
        let nsString = tableHtml as NSString
        let results = regex?.matches(in: tableHtml, options: [], range: NSRange(location: 0, length: nsString.length)) ?? []
        
        for result in results {
            guard result.numberOfRanges >= 9 else { continue }
            
            let lessonNumberRange = result.range(at: 1)
            let timeRange = result.range(at: 2)
            let lessonTypeRange = result.range(at: 3)
            let subjectRange = result.range(at: 4)
            let onlineInfoRange = result.range(at: 5)
            let auditoriumRange = result.range(at: 6)
            let groupsRange = result.range(at: 7)
            let teacherNameRange = result.range(at: 8)
            let teacherEmailRange = result.numberOfRanges > 9 ? result.range(at: 9) : NSRange(location: NSNotFound, length: 0)
            
            let lessonNumber = nsString.substring(with: lessonNumberRange)
            let timeString = nsString.substring(with: timeRange)
            let lessonTypeString = nsString.substring(with: lessonTypeRange)
            let subject = nsString.substring(with: subjectRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let onlineInfo = nsString.substring(with: onlineInfoRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let auditorium = nsString.substring(with: auditoriumRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let groups = nsString.substring(with: groupsRange).trimmingCharacters(in: .whitespacesAndNewlines)
            let teacherName = nsString.substring(with: teacherNameRange).trimmingCharacters(in: .whitespacesAndNewlines)
            
            let teacherEmail = teacherEmailRange.location != NSNotFound ? 
                nsString.substring(with: teacherEmailRange).trimmingCharacters(in: .whitespacesAndNewlines) : nil
            
            // Парсим время начала и конца
            let timeComponents = timeString.split(separator: "-")
            guard timeComponents.count == 2 else { continue }
            
            let startTime = String(timeComponents[0])
            let endTime = String(timeComponents[1])
            
            let lessonType = LessonType(from: lessonTypeString)
            let teacher = Teacher(name: teacherName, email: teacherEmail)
            
            let lesson = Lesson(
                pairNumber: Int(lessonNumber) ?? 0,
                timeStart: startTime,
                timeEnd: endTime,
                type: lessonType,
                subject: subject,
                room: auditorium.isEmpty ? nil : auditorium,
                teacher: teacherName.isEmpty ? nil : teacher,
                groups: groups.isEmpty ? [] : [groups],
                onlineLink: onlineInfo.isEmpty ? nil : onlineInfo
            )
            
            lessons.append(lesson)
        }
        
        return lessons.sorted { $0.pairNumber < $1.pairNumber }
    }
    
    /// Извлекает название группы из HTML (если возможно)
    private func extractGroupName(from html: String) -> String? {
        // Ищем название группы в HTML
        let groupPattern = #"(?:гр\.\s*|группа\s*)([А-Я0-9]+[А-Я]{3})"#
        let regex = try? NSRegularExpression(pattern: groupPattern, options: [.caseInsensitive])
        let nsString = html as NSString
        
        if let match = regex?.firstMatch(in: html, options: [], range: NSRange(location: 0, length: nsString.length)),
           match.numberOfRanges > 1 {
            let groupNameRange = match.range(at: 1)
            return nsString.substring(with: groupNameRange)
        }
        
        return nil
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