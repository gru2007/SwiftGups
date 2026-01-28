import Foundation

#if canImport(ActivityKit)
import ActivityKit
#endif

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

        // --- Данные следующей пары (если есть) ---
        var nextPairNumber: Int?
        var nextSubject: String?
        var nextRoom: String?
        var nextStartDate: Date?
        var nextEndDate: Date?
    }
}
#endif
