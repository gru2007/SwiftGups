import Foundation
import SwiftData

// MARK: - Модели данных для расписания вуза

/// Факультет/Институт
struct Faculty: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    
    init(id: String, name: String) {
        self.id = id
        self.name = name
    }
    
    /// Все доступные факультеты ДВГУПС
    static let allFaculties = [
        Faculty(id: "8", name: "Естественно-научный институт"),
        Faculty(id: "5", name: "Институт воздушных сообщений и мультитранспортных технологий"),
        Faculty(id: "11", name: "Институт интегрированных форм обучения"),
        Faculty(id: "9", name: "Институт международного сотрудничества"),
        Faculty(id: "4", name: "Институт транспортного строительства"),
        Faculty(id: "1", name: "Институт тяги и подвижного состава"),
        Faculty(id: "2", name: "Институт управления, автоматизации и телекоммуникаций"),
        Faculty(id: "3", name: "Институт экономики"),
        Faculty(id: "10", name: "Медицинское училище"),
        Faculty(id: "34", name: "Российско-китайский транспортный институт"),
        Faculty(id: "7", name: "Социально-гуманитарный институт"),
        Faculty(id: "19", name: "Хабаровский техникум железнодорожного транспорта"),
        Faculty(id: "6", name: "Электроэнергетический институт"),
        Faculty(id: "-1", name: "АмИЖТ"),
        Faculty(id: "-2", name: "БамИЖТ"),
        Faculty(id: "-3", name: "ПримИЖТ"),
        Faculty(id: "-4", name: "СахИЖТ")
    ]
}

/// Группа студентов
struct Group: Codable, Identifiable, Hashable {
    let id: String // GroupID из API
    let name: String // Название группы (например, "БО241ИСТ")
    let fullName: String // Полное название специальности
    let facultyId: String // ID факультета
    
    init(id: String, name: String, fullName: String, facultyId: String = "") {
        self.id = id
        self.name = name
        self.fullName = fullName
        self.facultyId = facultyId
    }
}

/// Тип занятия
enum LessonType: String, Codable, CaseIterable {
    case lecture = "Лекции"
    case practice = "Практика"
    case laboratory = "Лабораторные работы"
    case unknown = "Неизвестно"
    
    init(from rawValue: String) {
        switch rawValue.lowercased() {
        case "лекции":
            self = .lecture
        case "практика":
            self = .practice
        case "лабораторные работы":
            self = .laboratory
        default:
            self = .unknown
        }
    }
}

/// Преподаватель
struct Teacher: Codable {
    let name: String
    let email: String?
    
    init(name: String, email: String? = nil) {
        self.name = name
        self.email = email
    }
}

/// Пара (занятие)
struct Lesson: Codable, Identifiable {
    let id = UUID()
    let pairNumber: Int // Номер пары (1-6)
    let timeStart: String // Время начала (например, "09:50")
    let timeEnd: String // Время окончания (например, "11:20")
    let type: LessonType // Тип занятия
    let subject: String // Название предмета
    let room: String? // Аудитория
    let teacher: Teacher? // Преподаватель
    let groups: [String] // Группы, которые присутствуют на занятии
    let onlineLink: String? // Ссылка на онлайн-занятие
    let isEvenWeek: Bool? // Четная/нечетная неделя (может быть не указано)
    
    init(pairNumber: Int, timeStart: String, timeEnd: String, type: LessonType, 
         subject: String, room: String? = nil, teacher: Teacher? = nil, 
         groups: [String] = [], onlineLink: String? = nil, isEvenWeek: Bool? = nil) {
        self.pairNumber = pairNumber
        self.timeStart = timeStart
        self.timeEnd = timeEnd
        self.type = type
        self.subject = subject
        self.room = room
        self.teacher = teacher
        self.groups = groups
        self.onlineLink = onlineLink
        self.isEvenWeek = isEvenWeek
    }
}

/// День расписания
struct ScheduleDay: Codable, Identifiable {
    let id = UUID()
    let date: Date
    let weekday: String // Например, "Понедельник"
    let weekNumber: Int? // Номер недели (может быть не указан)
    let isEvenWeek: Bool? // Четная/нечетная неделя
    let lessons: [Lesson]
    
    init(date: Date, weekday: String, weekNumber: Int? = nil, 
         isEvenWeek: Bool? = nil, lessons: [Lesson] = []) {
        self.date = date
        self.weekday = weekday
        self.weekNumber = weekNumber
        self.isEvenWeek = isEvenWeek
        self.lessons = lessons
    }
}

/// Расписание для группы
struct Schedule: Codable, Identifiable {
    let id = UUID()
    let groupId: String
    let groupName: String
    let facultyId: String
    let startDate: Date // Начальная дата периода
    let endDate: Date // Конечная дата периода
    let days: [ScheduleDay]
    let lastUpdated: Date
    
    init(groupId: String, groupName: String, facultyId: String = "",
         startDate: Date, endDate: Date? = nil, 
         days: [ScheduleDay] = [], lastUpdated: Date = Date()) {
        self.groupId = groupId
        self.groupName = groupName
        self.facultyId = facultyId
        self.startDate = startDate
        self.endDate = endDate ?? startDate.addingTimeInterval(7 * 24 * 60 * 60) // По умолчанию неделя
        self.days = days
        self.lastUpdated = lastUpdated
    }
}



// MARK: - Вспомогательные расширения

extension Date {
    /// Форматтер для парсинга дат из API (например, "01.09.2025")
    static let apiDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd.MM.yyyy"
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter
    }()
    
    /// Форматтер для отображения дат пользователю
    static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy, EEEE"
        formatter.locale = Locale(identifier: "ru_RU")
        return formatter
    }()
}

// MARK: - Модели пользователя и персональных данных

/// Пользователь приложения (хранится локально с SwiftData)
@Model
class User {
    var id: UUID = UUID()
    var name: String = ""
    var facultyId: String = ""
    var facultyName: String = ""
    var groupId: String = ""
    var groupName: String = ""
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var isFirstTime: Bool = true
    
    init(name: String, facultyId: String, facultyName: String, groupId: String, groupName: String) {
        self.id = UUID()
        self.name = name
        self.facultyId = facultyId
        self.facultyName = facultyName
        self.groupId = groupId
        self.groupName = groupName
        self.createdAt = Date()
        self.updatedAt = Date()
        self.isFirstTime = true
    }
    
    func updateGroup(groupId: String, groupName: String) {
        self.groupId = groupId
        self.groupName = groupName
        self.updatedAt = Date()
    }
    
    func updateFaculty(facultyId: String, facultyName: String) {
        self.facultyId = facultyId
        self.facultyName = facultyName
        self.updatedAt = Date()
    }
}

/// Домашнее задание (синхронизируется через iCloud)
@Model
class Homework {
    var id: UUID = UUID()
    var title: String = ""
    var subject: String = ""
    var desc: String = ""
    var dueDate: Date = Date()
    var isCompleted: Bool = false
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var priority: HomeworkPriority?
    var attachments: [String] = [] // Пути к файлам или ссылки
    
    init(title: String, subject: String, description: String, dueDate: Date, priority: HomeworkPriority = .medium) {
        self.id = UUID()
        self.title = title
        self.subject = subject
        self.desc = description
        self.dueDate = dueDate
        self.isCompleted = false
        self.createdAt = Date()
        self.updatedAt = Date()
        self.priority = priority
        self.attachments = []
    }
    
    var effectivePriority: HomeworkPriority {
        return priority ?? .medium
    }
    
    func toggle() {
        isCompleted.toggle()
        updatedAt = Date()
    }
    
    func addAttachment(_ attachment: String) {
        attachments.append(attachment)
        updatedAt = Date()
    }
}

/// Приоритет домашнего задания
enum HomeworkPriority: String, Codable, CaseIterable {
    case low = "Низкий"
    case medium = "Средний"
    case high = "Высокий"
    case urgent = "Срочный"
    
    var color: String {
        switch self {
        case .low: return "gray"
        case .medium: return "blue"
        case .high: return "orange"
        case .urgent: return "red"
        }
    }
}

/// Время пар (расписание звонков)
struct LessonTime: Identifiable, Codable {
    let id = UUID()
    let number: Int
    let startTime: String
    let endTime: String
    
    var timeRange: String {
        return "\(startTime) - \(endTime)"
    }
    
    /// Стандартное расписание звонков ДВГУПС
    static let schedule = [
        LessonTime(number: 1, startTime: "8:05", endTime: "9:35"),
        LessonTime(number: 2, startTime: "9:50", endTime: "11:20"),
        LessonTime(number: 3, startTime: "11:35", endTime: "13:05"),
        LessonTime(number: 4, startTime: "13:35", endTime: "15:05"),
        LessonTime(number: 5, startTime: "15:15", endTime: "16:45"),
        LessonTime(number: 6, startTime: "16:55", endTime: "18:25")
    ]
    
    static func timeForPair(_ number: Int) -> LessonTime? {
        return schedule.first { $0.number == number }
    }
}

extension String {
    /// Извлекает email из HTML строки
    func extractEmail() -> String? {
        let emailRegex = try? NSRegularExpression(pattern: "mailto:([\\w\\.-]+@[\\w\\.-]+)", options: [])
        let nsString = self as NSString
        let results = emailRegex?.matches(in: self, options: [], range: NSRange(location: 0, length: nsString.length))
        
        if let match = results?.first, match.numberOfRanges > 1 {
            let emailRange = match.range(at: 1)
            return nsString.substring(with: emailRange)
        }
        return nil
    }
    
    /// Очищает HTML теги из строки
    func stripHTMLTags() -> String {
        return self.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression, range: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    /// Проверяет, содержит ли строка URL
    var containsURL: Bool {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        if let detector = detector {
            let range = NSRange(location: 0, length: self.count)
            return detector.firstMatch(in: self, options: [], range: range) != nil
        }
        return false
    }
    
    /// Извлекает URLs из строки
    var extractedURLs: [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        guard let detector = detector else { return [] }
        
        let range = NSRange(location: 0, length: self.count)
        let matches = detector.matches(in: self, options: [], range: range)
        
        return matches.compactMap { match in
            guard let range = Range(match.range, in: self) else { return nil }
            return URL(string: String(self[range]))
        }
    }
}

// MARK: - Новости

/// Элемент новостей
struct NewsItem: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let description: String
    let fullText: String
    let imageURL: String?
    let date: Date
    let hits: Int
    
    init(id: String, title: String, description: String, fullText: String, imageURL: String?, date: Date, hits: Int = 0) {
        self.id = id
        self.title = title
        self.description = description
        self.fullText = fullText
        self.imageURL = imageURL?.isEmpty == false ? imageURL : nil
        self.date = date
        self.hits = hits
    }
    
    /// Форматтер для парсинга даты из API новостей
    static let newsDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return formatter
    }()
    
    /// Форматтер для отображения даты новостей пользователю  
    static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy, HH:mm"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return formatter
    }()
}

/// Коллекция новостей с поддержкой пагинации
struct NewsResponse: Codable {
    let items: [NewsItem]
    let hasMorePages: Bool
    let nextOffset: Int
    
    init(items: [NewsItem], hasMorePages: Bool = false, nextOffset: Int = 0) {
        self.items = items
        self.hasMorePages = hasMorePages
        self.nextOffset = nextOffset
    }
}

/// Ошибки загрузки новостей
enum NewsError: Error, LocalizedError {
    case invalidURL
    case noData
    case parseError(String)
    case networkError(Error)
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL новостей"
        case .noData:
            return "Нет данных в ответе сервера"
        case .parseError(let message):
            return "Ошибка парсинга новостей: \(message)"
        case .networkError(let error):
            return "Ошибка сети: \(error.localizedDescription)"
        }
    }
}
