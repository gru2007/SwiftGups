import Foundation

// MARK: - Модели данных для расписания вуза

/// Факультет/Институт
struct Faculty: Codable, Identifiable {
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
struct Group: Codable, Identifiable {
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
}
