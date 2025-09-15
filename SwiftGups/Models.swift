import Foundation
import SwiftData
import CloudKit

// MARK: - Модели данных для расписания вуза

/*
 ВАЖНО: Синхронизация с CloudKit
 
 Модели User и Homework настроены для автоматической синхронизации с iCloud:
 - Все атрибуты имеют значения по умолчанию (требование CloudKit)
 - Удалены unique constraints - CloudKit их не поддерживает
 - Используется .private CloudKit база данных для персональных данных
 - CloudKit автоматически разрешает конфликты при синхронизации между устройствами
 
 Синхронизация происходит автоматически при наличии активного iCloud аккаунта.
 При отсутствии iCloud данные сохраняются локально и синхронизируются при подключении.
 */

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
    
    /// Формирует текст для обмена
    var shareText: String {
        var text = "📅 Пара №\(pairNumber)\n"
        text += "🕰 Время: \(timeStart) - \(timeEnd)\n"
        text += "📚 \(type.rawValue): \(subject)\n"
        
        if let room = room, !room.isEmpty {
            text += "📍 Аудитория: \(room)\n"
        }
        
        if let teacher = teacher, !teacher.name.isEmpty {
            text += "👨‍🏫 Преподаватель: \(teacher.name)\n"
            if let email = teacher.email, !email.isEmpty {
                text += "✉️ Email: \(email)\n"
            }
        }
        
        if !groups.isEmpty {
            text += "👥 Группы: \(groups.joined(separator: ", "))\n"
        }
        
        if let onlineLink = onlineLink, !onlineLink.isEmpty {
            text += "💻 Дистанционно: \(onlineLink)\n"
        }
        
        text += "\n🎓 Приложение SwiftGups"
        
        return text
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

/// Пользователь приложения (синхронизируется через iCloud)
@Model
class User {
    var id: UUID = UUID()
    var name: String = ""
    var facultyId: String = ""
    var facultyName: String = ""
    var groupId: String = ""
    var groupName: String = ""
    var createdAt: Date = Date()
    var isFirstTime: Bool = true
    
    init(name: String, facultyId: String, facultyName: String, groupId: String, groupName: String) {
        self.id = UUID()
        self.name = name
        self.facultyId = facultyId
        self.facultyName = facultyName
        self.groupId = groupId
        self.groupName = groupName
        self.createdAt = Date()
        self.isFirstTime = true
    }
    
    func updateGroup(groupId: String, groupName: String) {
        self.groupId = groupId
        self.groupName = groupName
    }
    
    func updateFaculty(facultyId: String, facultyName: String) {
        self.facultyId = facultyId
        self.facultyName = facultyName
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
    var priority: HomeworkPriority = HomeworkPriority.medium
    var attachments: [String] = [] // Пути к файлам или ссылки
    
    init(title: String, subject: String, description: String, dueDate: Date, priority: HomeworkPriority = .medium) {
        self.id = UUID()
        self.title = title
        self.subject = subject
        self.desc = description
        self.dueDate = dueDate
        self.isCompleted = false
        self.createdAt = Date()
        self.priority = priority
        self.attachments = []
    }
    
    func toggle() {
        isCompleted.toggle()
    }
    
    func addAttachment(_ attachment: String) {
        attachments.append(attachment)
    }
    
    func removeAttachment(_ attachment: String) {
        attachments.removeAll { $0 == attachment }
    }
    
    var imageAttachments: [String] {
        return attachments.filter { attachment in
            let lowercased = attachment.lowercased()
            return lowercased.hasSuffix(".jpg") || 
                   lowercased.hasSuffix(".jpeg") || 
                   lowercased.hasSuffix(".png") || 
                   lowercased.hasSuffix(".heic") ||
                   lowercased.hasSuffix(".heif")
        }
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

/// Расширение для коллекции пар
extension Collection where Element == Lesson {
    /// Возвращает количество пар по типам
    var lessonTypeStats: [LessonType: Int] {
        var stats: [LessonType: Int] = [:]
        for lesson in self {
            stats[lesson.type, default: 0] += 1
        }
        return stats
    }
    
    /// Возвращает пары с онлайн-ссылками
    var onlineLessons: [Element] {
        return self.filter { $0.onlineLink != nil && !$0.onlineLink!.isEmpty }
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
    
    /// Сокращает текст до указанной длины
    func truncated(to length: Int) -> String {
        guard self.count > length else { return self }
        return String(self.prefix(length)) + "..."
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

/// Расширение для расписания
extension Schedule {
    /// Общая статистика по типам пар
    var overallStats: [LessonType: Int] {
        let allLessons = days.flatMap { $0.lessons }
        return allLessons.lessonTypeStats
    }
    
    /// Общее количество пар
    var totalLessonsCount: Int {
        return days.reduce(0) { $0 + $1.lessons.count }
    }
    
    /// Количество онлайн пар
    var onlineLessonsCount: Int {
        let allLessons = days.flatMap { $0.lessons }
        return allLessons.onlineLessons.count
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

// MARK: - Connect функционал

/// Модель лайков для CloudKit Public Database
struct ConnectLike: Codable {
    let id: String
    let timestamp: Date
    let deviceIdentifier: String // для предотвращения спама
    
    init(deviceIdentifier: String) {
        self.id = UUID().uuidString
        self.timestamp = Date()
        self.deviceIdentifier = deviceIdentifier
    }
    
    /// Преобразование в CloudKit CKRecord
    func toCKRecord() -> CKRecord {
        let record = CKRecord(recordType: "ConnectLike")
        record["timestamp"] = timestamp as NSDate
        record["deviceIdentifier"] = deviceIdentifier as NSString
        return record
    }
    
    /// Создание из CloudKit CKRecord
    static func fromCKRecord(_ record: CKRecord) -> ConnectLike? {
        guard let timestamp = record["timestamp"] as? Date,
              let deviceIdentifier = record["deviceIdentifier"] as? String else {
            return nil
        }
        
        return ConnectLike(
            id: record.recordID.recordName,
            timestamp: timestamp,
            deviceIdentifier: deviceIdentifier
        )
    }
    
    private init(id: String, timestamp: Date, deviceIdentifier: String) {
        self.id = id
        self.timestamp = timestamp
        self.deviceIdentifier = deviceIdentifier
    }
}

/// Статистика Connect
struct ConnectStats: Codable {
    let totalLikes: Int
    let lastUpdated: Date
    let bridgesBuilt: Int // метафора соединений
    
    init(totalLikes: Int = 0, bridgesBuilt: Int = 0) {
        self.totalLikes = totalLikes
        self.lastUpdated = Date()
        self.bridgesBuilt = bridgesBuilt
    }
    
    var bridgesBuiltText: String {
        let bridges = bridgesBuilt
        switch bridges {
        case 0:
            return "Мы готовы к соединению"
        case 1:
            return "Первый мост построен"
        case 2...5:
            return "Начальная связь установлена"
        case 6...10:
            return "Первые мосты построены"
        case 11...25:
            return "Соединения крепнут"
        case 26...50:
            return "Сеть соединений расширяется"
        case 51...100:
            return "Мосты объединяют всех"
        case 101...200:
            return "Мощная сеть сформирована"
        case 201...350:
            return "Неразрушимые связи"
        case 351...500:
            return "Коммюнити процветает"
        case 501...750:
            return "Мастер создания связей"
        case 751...1000:
            return "Легендарный строитель мостов"
        case 1001...1500:
            return "Архитектор связей"
        case 1501...2000:
            return "Мы создали сильное сообщество"
        case 2001...3000:
            return "Гений коннекта"
        case 3001...5000:
            return "Мы переосмыслили социальные связи"
        case 5001...10000:
            return "Лидер цифровой эволюции"
        default:
            return "Мы создали новую реальность"
        }
    }
    
    /// Проверяет, достиг ли пользователь специального уровня для пасхалки Кодзимы
    var hasKojimaAchievement: Bool {
        return bridgesBuilt >= 50  // Пониженный порог для тестирования (было 42)
    }
    
    /// Текст достижения для показа специального статуса
    var achievementLevel: String {
        switch bridgesBuilt {
        case 0...5:
            return "Новичок"
        case 6...25:
            return "Строитель"
        case 26...100:
            return "Архитектор"
        case 101...500:
            return "Мастер"
        case 501...1000:
            return "Легенда"
        case 1001...2000:
            return "Миф"
        default:
            return "Бог Коннекта"
        }
    }
}

