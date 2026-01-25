import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

/// Атрибуты Live Activity “текущая пара”.
///
/// Важно: структура должна совпадать с определением в основном приложении.
struct CurrentLessonActivityAttributes: Codable, Hashable {
    let groupId: String
    let groupName: String
}

#if canImport(ActivityKit)
@available(iOS 16.1, *)
extension CurrentLessonActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        /// "current" | "next"
        var kind: String
        
        var pairNumber: Int
        var subject: String
        var room: String?
        var startDate: Date
        var endDate: Date
    }
}
#endif

