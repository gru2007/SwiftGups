import Foundation

/// Данные, необходимые, чтобы показать “текущую/следующую пару” в UI/Live Activity.
struct ScheduleLessonContext {
    enum Kind: String, Codable, Hashable {
        case current
        case next
    }
    
    let kind: Kind
    let lesson: Lesson
    let startDate: Date
    let endDate: Date
    
    var timeRangeText: String {
        let formatter = DateFormatter.timeFormatter
        return "\(formatter.string(from: startDate)) – \(formatter.string(from: endDate))"
    }
}

extension TimeZone {
    /// ДВГУПС (Хабаровск) живёт в зоне Asia/Vladivostok (UTC+10).
    static let dvgups: TimeZone = TimeZone(identifier: "Asia/Vladivostok") ?? .current
}

extension Calendar {
    static let dvgups: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "ru_RU")
        cal.timeZone = .dvgups
        return cal
    }()
}

extension Schedule {
    /// Возвращает контекст “текущей” или “следующей” пары относительно указанной даты.
    ///
    /// - Important: используем календарь/таймзону ДВГУПС, чтобы корректно сопоставлять дни и время пар.
    func currentOrNextLessonContext(at date: Date) -> ScheduleLessonContext? {
        let cal = Calendar.dvgups
        let today = cal.startOfDay(for: date)
        
        guard let day = days.first(where: { cal.isDate(cal.startOfDay(for: $0.date), inSameDayAs: today) }) else {
            return nil
        }
        
        // Уроки у нас уже отсортированы в APIClient (pairNumber/timeStart), но на всякий случай.
        let lessons = day.lessons.sorted {
            if $0.pairNumber != $1.pairNumber { return $0.pairNumber < $1.pairNumber }
            return $0.timeStart < $1.timeStart
        }
        
        // Сначала пытаемся найти текущую пару.
        for lesson in lessons {
            guard let start = cal.date(on: day.date, hhmm: lesson.timeStart),
                  let end = cal.date(on: day.date, hhmm: lesson.timeEnd) else { continue }
            
            if date >= start && date < end {
                return ScheduleLessonContext(kind: .current, lesson: lesson, startDate: start, endDate: end)
            }
        }
        
        // Если текущей нет — ищем ближайшую следующую на сегодня.
        var nextCandidate: (lesson: Lesson, start: Date, end: Date)?
        for lesson in lessons {
            guard let start = cal.date(on: day.date, hhmm: lesson.timeStart),
                  let end = cal.date(on: day.date, hhmm: lesson.timeEnd) else { continue }
            
            if start > date {
                if let existing = nextCandidate {
                    if start < existing.start { nextCandidate = (lesson, start, end) }
                } else {
                    nextCandidate = (lesson, start, end)
                }
            }
        }
        
        if let nextCandidate {
            return ScheduleLessonContext(kind: .next, lesson: nextCandidate.lesson, startDate: nextCandidate.start, endDate: nextCandidate.end)
        }
        
        return nil
    }
}

private extension Calendar {
    func date(on baseDate: Date, hhmm: String) -> Date? {
        let parts = hhmm
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":")
            .map(String.init)
        
        guard parts.count >= 2,
              let h = Int(parts[0]),
              let m = Int(parts[1]) else { return nil }
        
        var comps = dateComponents([.year, .month, .day], from: baseDate)
        comps.hour = h
        comps.minute = m
        comps.second = 0
        
        return self.date(from: comps)
    }
}

