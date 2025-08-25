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