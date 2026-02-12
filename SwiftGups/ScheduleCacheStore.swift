import Foundation

/// Простой дисковый кэш для оффлайн-режима.
///
/// Задача: при пропаже интернета показывать последнее успешно загруженное расписание,
/// а также (по возможности) ранее загруженные списки институтов и групп.
struct ScheduleCacheStore {
    enum Key: Hashable {
        case faculties
        case groups(facultyId: String)
        case schedule(groupId: String, weekStart: String) // yyyy-MM-dd
    }
    
    private let fileManager = FileManager.default
    private let baseDirectory: URL
    
    init() {
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        self.baseDirectory = caches.appendingPathComponent("SwiftGupsCache", isDirectory: true)
        try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
    }
    
    func write<T: Encodable>(_ value: T, for key: Key) {
        let url = fileURL(for: key)
        do {
            let data = try JSONEncoder().encode(value)
            try data.write(to: url, options: [.atomic])
        } catch {
            // Кэш — best-effort: ошибки записи не пробрасываем в UI.
        }
    }
    
    func read<T: Decodable>(_ type: T.Type, for key: Key) -> T? {
        let url = fileURL(for: key)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            return nil
        }
    }
    
    private func fileURL(for key: Key) -> URL {
        let filename: String
        switch key {
        case .faculties:
            filename = "faculties.json"
        case .groups(let facultyId):
            filename = "groups_faculty_\(sanitize(facultyId)).json"
        case .schedule(let groupId, let weekStart):
            filename = "schedule_group_\(sanitize(groupId))_week_\(sanitize(weekStart)).json"
        }
        return baseDirectory.appendingPathComponent(filename)
    }
    
    private func sanitize(_ value: String) -> String {
        // Чтобы не было проблем с путями, оставляем только [A-Za-z0-9-_]
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        return value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }.reduce(into: "") { $0.append($1) }
    }
}

