import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct CurrentLessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CurrentLessonActivityAttributes.self) { context in
            // Lock Screen / banner UI
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text("Пара \(context.state.pairNumber)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.subject)
                            .font(.headline)
                            .lineLimit(1)
                        
                        if let room = context.state.room, !room.isEmpty {
                            Text(room)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(kindTitle(context.state.kind))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text(timeRange(context: context))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            } compactLeading: {
                Text("№\(context.state.pairNumber)")
                    .font(.caption2)
            } compactTrailing: {
                Text(kindShort(context.state.kind))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } minimal: {
                Text("№\(context.state.pairNumber)")
                    .font(.caption2)
            }
        }
    }
    
    private func kindTitle(_ kind: String) -> String {
        switch kind {
        case "current": return "Сейчас"
        case "next": return "Далее"
        default: return ""
        }
    }
    
    private func kindShort(_ kind: String) -> String {
        switch kind {
        case "current": return "•"
        case "next": return "→"
        default: return ""
        }
    }
    
    private func timeRange(context: ActivityViewContext<CurrentLessonActivityAttributes>) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let s = f.string(from: context.state.startDate)
        let e = f.string(from: context.state.endDate)
        return "\(s)–\(e)"
    }
}

@available(iOS 16.1, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<CurrentLessonActivityAttributes>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(kindTitle(context.state.kind))
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("№\(context.state.pairNumber)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Text(context.state.subject)
                .font(.headline)
                .lineLimit(2)
            
            HStack {
                Text(timeRange)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if let room = context.state.room, !room.isEmpty {
                    Text(room)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            Text(context.attributes.groupName)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .activityBackgroundTint(Color(.systemBackground))
        .activitySystemActionForegroundColor(.blue)
    }
    
    private var timeRange: String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let s = f.string(from: context.state.startDate)
        let e = f.string(from: context.state.endDate)
        return "\(s) – \(e)"
    }
    
    private func kindTitle(_ kind: String) -> String {
        switch kind {
        case "current": return "Сейчас"
        case "next": return "Следующая"
        default: return ""
        }
    }
}

