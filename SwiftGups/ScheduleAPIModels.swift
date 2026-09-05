import Foundation

// MARK: - Форматы API расписания
//
// С 2026 года группы вуза переехали на новый API:
//   • справочник групп     — /api/v1/timetable/groups/options?page=&limit=&q=
//   • календарь недель     — /api/v1/timetable/weeks
//   • расписание           — /api/v1/timetable/schedule (payload расширен)
//
// Техникумы, входящие в ассоциацию, остались на старом API:
//   • справочник факультетов — /api/v1/timetable/faculties
//   • группы факультета      — /api/v1/timetable/groups/by-faculty
//
// Поэтому новый формат — основной путь, старый живёт как фолбек: все поля,
// которых нет в старой отдаче, объявлены опциональными.

// MARK: - Учебные недели (новый API)

/// Учебная неделя из `/api/v1/timetable/weeks`.
///
/// Веб-версия строит навигацию именно по этим неделям, а не по календарным:
/// у вуза семестр может начинаться с середины недели, а нумерация («4 неделя»)
/// вычисляется сервером.
struct ScheduleWeek: Codable, Identifiable, Hashable {
    let id: Int
    let name: String
    let startDate: Date
    let endDate: Date
    let isCurrent: Bool

    /// Попадает ли дата в эту неделю (по календарным дням).
    func contains(_ date: Date, calendar: Calendar = ScheduleWeek.universityCalendar) -> Bool {
        let day = calendar.startOfDay(for: date)
        return day >= calendar.startOfDay(for: startDate) && day <= calendar.startOfDay(for: endDate)
    }

    /// Границы недели сервер задаёт в местном времени вуза, поэтому и сравниваем в нём:
    /// иначе для пользователя в другом часовом поясе неделя «съезжает» на день.
    static let universityCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Vladivostok") ?? .current
        return calendar
    }()
}

/// DTO недели. Сервер отдаёт даты в двух видах: `startDate` = "31.08.2026"
/// и `startDateObj` = "2026-08-31". Берём ISO-вариант, при его отсутствии — обычный.
struct ScheduleWeekDTO: Decodable {
    let id: Int?
    let name: String?
    let startDate: String?
    let endDate: String?
    let startDateObj: String?
    let endDateObj: String?
    let isCurrent: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLooseInt(forKey: .id)
        name = container.decodeLooseString(forKey: .name)
        startDate = container.decodeLooseString(forKey: .startDate)
        endDate = container.decodeLooseString(forKey: .endDate)
        startDateObj = container.decodeLooseString(forKey: .startDateObj)
        endDateObj = container.decodeLooseString(forKey: .endDateObj)
        isCurrent = try? container.decodeIfPresent(Bool.self, forKey: .isCurrent)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, startDate, endDate, startDateObj, endDateObj, isCurrent
    }

    /// Собирает доменную модель. Возвращает nil, если даты нечитаемы.
    func makeWeek(fallbackId: Int) -> ScheduleWeek? {
        guard let start = Self.date(iso: startDateObj, dotted: startDate),
              let end = Self.date(iso: endDateObj, dotted: endDate) else { return nil }

        let resolvedId = id ?? fallbackId
        let resolvedName = name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty

        return ScheduleWeek(
            id: resolvedId,
            name: resolvedName ?? "\(resolvedId) неделя",
            startDate: start,
            endDate: end,
            isCurrent: isCurrent ?? false
        )
    }

    private static func date(iso: String?, dotted: String?) -> Date? {
        if let iso, let parsed = DateFormatter.serverDateFormatter.date(from: iso) { return parsed }
        if let dotted, let parsed = DateFormatter.apiDateFormatter.date(from: dotted) { return parsed }
        return nil
    }
}

// MARK: - Справочник групп (новый API)

/// Страница справочника групп из `/api/v1/timetable/groups/options`.
struct GroupOptionsPage {
    let groups: [Group]
    let page: Int
    let limit: Int
    let hasMore: Bool
}

/// DTO ответа `/groups/options`: `{ items, page, limit, has_more }`.
struct GroupOptionsPageDTO: Decodable {
    let items: [GroupOptionDTO]
    let page: Int?
    let limit: Int?
    let hasMore: Bool?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = (try? container.decodeIfPresent([GroupOptionDTO].self, forKey: .items)) ?? []
        page = container.decodeLooseInt(forKey: .page)
        limit = container.decodeLooseInt(forKey: .limit)
        hasMore = try? container.decodeIfPresent(Bool.self, forKey: .hasMore)
    }

    private enum CodingKeys: String, CodingKey {
        case items
        case page
        case limit
        case hasMore = "has_more"
    }

    func makePage(requestedPage: Int, requestedLimit: Int) -> GroupOptionsPage {
        let groups = items.compactMap { $0.makeGroup() }
        // `has_more` — источник правды, но если сервер его не прислал,
        // ориентируемся на заполненность страницы.
        let more = hasMore ?? (items.count >= requestedLimit && requestedLimit > 0)
        return GroupOptionsPage(
            groups: groups,
            page: page ?? requestedPage,
            limit: limit ?? requestedLimit,
            hasMore: more
        )
    }
}

/// Элемент справочника групп: `{ id, name, field, faculty_id }`.
struct GroupOptionDTO: Decodable {
    let id: String?
    let name: String?
    let field: String?
    let facultyId: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLooseString(forKey: .id)
        name = container.decodeLooseString(forKey: .name)
        field = container.decodeLooseString(forKey: .field)
        facultyId = container.decodeLooseString(forKey: .facultyId)
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, field
        case facultyId = "faculty_id"
    }

    func makeGroup() -> Group? {
        let groupId = (id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let groupName = (name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !groupId.isEmpty, !groupName.isEmpty else { return nil }

        return Group(
            id: groupId,
            name: groupName,
            fullName: (field ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
            facultyId: (facultyId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}

// MARK: - Расписание

/// Элемент расписания из `/api/v1/timetable/schedule`.
///
/// Новый формат добавил `day_layout_id`, `calendar_id`, `begins_at`/`ends_at`
/// и расширенные сведения о группах и преподавателях. Старый формат присылает
/// тот же каркас без этих полей, поэтому обязательных полей здесь нет вовсе:
/// одна кривая пара не должна ронять неделю целиком.
struct ScheduleItemDTO: Decodable {
    let startTime: String?
    let endTime: String?
    let date: String?
    let dayLayoutId: String?
    let calendarId: String?
    let lessonData: LessonDataDTO?

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        startTime = container.decodeLooseString(forKey: .startTime)
        endTime = container.decodeLooseString(forKey: .endTime)
        date = container.decodeLooseString(forKey: .date)
        dayLayoutId = container.decodeLooseString(forKey: .dayLayoutId)
        calendarId = container.decodeLooseString(forKey: .calendarId)
        lessonData = try? container.decodeIfPresent(LessonDataDTO.self, forKey: .lessonData)
    }

    private enum CodingKeys: String, CodingKey {
        case startTime = "start_time"
        case endTime = "end_time"
        case date
        case dayLayoutId = "day_layout_id"
        case calendarId = "calendar_id"
        case lessonData = "lesson_data"
    }

    struct LessonDataDTO: Decodable {
        let courseType: NamedDTO?
        let courseSubject: NamedDTO?
        let teacherList: [TeacherDTO]
        let studentList: [StudentDTO]
        let studyPlace: StudyPlaceDTO?
        /// Новый формат: полная отметка времени начала ("2026-09-01T11:35:00").
        let beginsAt: String?
        let endsAt: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            courseType = try? container.decodeIfPresent(NamedDTO.self, forKey: .courseType)
            courseSubject = try? container.decodeIfPresent(NamedDTO.self, forKey: .courseSubject)
            teacherList = (try? container.decodeIfPresent([TeacherDTO].self, forKey: .teacherList)) ?? []
            studentList = (try? container.decodeIfPresent([StudentDTO].self, forKey: .studentList)) ?? []
            studyPlace = try? container.decodeIfPresent(StudyPlaceDTO.self, forKey: .studyPlace)
            beginsAt = container.decodeLooseString(forKey: .beginsAt)
            endsAt = container.decodeLooseString(forKey: .endsAt)
        }

        private enum CodingKeys: String, CodingKey {
            case courseType = "course_type"
            case courseSubject = "course_subject"
            case teacherList = "teacher_list"
            case studentList = "student_list"
            case studyPlace = "study_place"
            case beginsAt = "begins_at"
            case endsAt = "ends_at"
        }
    }

    /// Общий вид для `course_type` / `course_subject`.
    struct NamedDTO: Decodable {
        let name: String?
        let nameAbbr: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = container.decodeLooseString(forKey: .name)
            nameAbbr = container.decodeLooseString(forKey: .nameAbbr)
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case nameAbbr = "name_abbr"
        }
    }

    struct TeacherDTO: Decodable {
        let id: String?
        let name: String?
        let nameAbbr: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.decodeLooseString(forKey: .id)
            name = container.decodeLooseString(forKey: .name)
            nameAbbr = container.decodeLooseString(forKey: .nameAbbr)
        }

        private enum CodingKeys: String, CodingKey {
            case id, name
            case nameAbbr = "name_abbr"
        }

        /// Короткое имя («Трофимович П. Н.») предпочтительнее — оно помещается в карточку пары.
        var displayName: String? {
            let abbr = nameAbbr?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let abbr, !abbr.isEmpty { return abbr }
            let full = name?.trimmingCharacters(in: .whitespacesAndNewlines)
            return (full?.isEmpty == false) ? full : nil
        }
    }

    struct StudentDTO: Decodable {
        let name: String?
        let nameAbbr: String?
        let studentGroupName: String?
        let facultyName: String?
        let facultyNameAbbr: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = container.decodeLooseString(forKey: .name)
            nameAbbr = container.decodeLooseString(forKey: .nameAbbr)
            studentGroupName = container.decodeLooseString(forKey: .studentGroupName)
            facultyName = container.decodeLooseString(forKey: .facultyName)
            facultyNameAbbr = container.decodeLooseString(forKey: .facultyNameAbbr)
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case nameAbbr = "name_abbr"
            case studentGroupName = "student_group_name"
            case facultyName = "faculty_name"
            case facultyNameAbbr = "faculty_name_abbr"
        }

        /// Название группы без «шапки» вида «БОД21ИСС [2025] ИТСС (бак) - ИСиС».
        var groupName: String? {
            for candidate in [studentGroupName, nameAbbr, name] {
                let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
                if let value, !value.isEmpty { return value }
            }
            return nil
        }
    }

    struct StudyPlaceDTO: Decodable {
        let name: String?
        let ownerName: String?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = container.decodeLooseString(forKey: .name)
            ownerName = container.decodeLooseString(forKey: .ownerName)
        }

        private enum CodingKeys: String, CodingKey {
            case name
            case ownerName = "owner_name"
        }
    }

    // MARK: Разбор

    /// Дата пары: `date` ("2026-09-01"), иначе — дата из `begins_at`.
    var lessonDate: Date? {
        if let date, let parsed = DateFormatter.serverDateFormatter.date(from: date) {
            return parsed
        }
        if let beginsAt = lessonData?.beginsAt,
           let dayPart = beginsAt.split(separator: "T").first {
            return DateFormatter.serverDateFormatter.date(from: String(dayPart))
        }
        return nil
    }

    /// Время начала в виде "11:35".
    var startHHmm: String? {
        ScheduleTimeFormat.hhmm(from: startTime ?? Self.timePart(of: lessonData?.beginsAt), roundingUp: false)
    }

    /// Время окончания в виде "13:05".
    ///
    /// Новый API отдаёт «13:04:59» (конец пары минус секунда) — округляем вверх,
    /// иначе в интерфейсе получается «13:04» вместо привычного «13:05».
    var endHHmm: String? {
        ScheduleTimeFormat.hhmm(from: endTime ?? Self.timePart(of: lessonData?.endsAt), roundingUp: true)
    }

    private static func timePart(of timestamp: String?) -> String? {
        guard let timestamp, let time = timestamp.split(separator: "T").last else { return nil }
        return String(time)
    }
}

// MARK: - Время пар

enum ScheduleTimeFormat {
    /// "11:35:00" → "11:35"; "13:04:59" при `roundingUp` → "13:05".
    static func hhmm(from raw: String?, roundingUp: Bool) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }

        let parts = raw.split(separator: ":")
        guard parts.count >= 2, var hour = Int(parts[0]), var minute = Int(parts[1]) else {
            return raw
        }

        let seconds = parts.count >= 3 ? (Int(parts[2]) ?? 0) : 0
        if roundingUp, seconds >= 30 {
            minute += 1
            if minute >= 60 {
                minute -= 60
                hour = (hour + 1) % 24
            }
        }

        return String(format: "%02d:%02d", hour, minute)
    }

    /// Минуты от полуночи для сортировки пар внутри дня.
    static func minutesSinceMidnight(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return 0 }
        return hour * 60 + minute
    }

    /// Номер пары по расписанию звонков. `nil`, если время не совпало
    /// (у техникумов ассоциации своя сетка) — тогда нумеруем по порядку в дне.
    static func bellPairNumber(forStartTime hhmm: String) -> Int? {
        let target = minutesSinceMidnight(hhmm)
        for bell in LessonTime.schedule where minutesSinceMidnight(bell.startTime) == target {
            return bell.number
        }
        return nil
    }
}

// MARK: - Мягкое декодирование

extension KeyedDecodingContainer {
    /// Декодирует значение как строку, даже если сервер прислал число.
    ///
    /// Идентификаторы в API приходят строками ("60584"), но в отдельных
    /// эндпоинтах встречались числа — не роняем разбор из-за этого.
    func decodeLooseString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return String(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value == value.rounded() ? String(Int(value)) : String(value)
        }
        return nil
    }

    /// Декодирует значение как число, даже если сервер прислал строку.
    func decodeLooseInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) { return value }
        if let value = try? decodeIfPresent(String.self, forKey: key) { return Int(value) }
        if let value = try? decodeIfPresent(Double.self, forKey: key) { return Int(value) }
        return nil
    }
}
