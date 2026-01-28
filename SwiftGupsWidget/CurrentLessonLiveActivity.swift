import ActivityKit
import SwiftUI
import WidgetKit

@available(iOS 16.1, *)
struct CurrentLessonLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CurrentLessonActivityAttributes.self) { context in
            LockScreenView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded view
                DynamicIslandExpandedRegion(.leading) {
                    // Аудитория слева (только текст, максимум 8 символов)
                    if let room = context.state.room, !room.isEmpty {
                        Text(formatRoom(room))
                            .font(.system(.subheadline, design: .default))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                
                DynamicIslandExpandedRegion(.trailing) {
                    // Время следующего события справа
                    TimerView(
                        kind: context.state.kind,
                        startDate: context.state.startDate,
                        endDate: context.state.endDate,
                        nextStartDate: context.state.nextStartDate
                    )
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(.primary)
                }
                
                DynamicIslandExpandedRegion(.center) {
                    // Текущая пара
                    VStack(alignment: .leading, spacing: 4) {
                        Text(shortenSubject(context.state.subject, maxLength: 25))
                            .font(.system(.headline, design: .default))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.8)
                        
                        HStack(spacing: 6) {
                            Text("№\(context.state.pairNumber)")
                                .font(.system(.caption, design: .default).weight(.medium))
                                .foregroundStyle(.blue)
                            
                            Text(timeRange(context: context))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                DynamicIslandExpandedRegion(.bottom) {
                    // Следующая пара
                    if let next = context.state.nextSubject, !next.isEmpty {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right")
                                .font(.system(.caption2))
                                .foregroundStyle(.tertiary)
                            
                            Text(shortenSubject(next, maxLength: 20))
                                .font(.system(.subheadline, design: .default))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .minimumScaleFactor(0.8)
                            
                            if let nextNum = context.state.nextPairNumber {
                                Text("№\(nextNum)")
                                    .font(.system(.caption2, design: .default).weight(.medium))
                                    .foregroundStyle(.blue)
                            }
                            
                            if let nextRoom = context.state.nextRoom, !nextRoom.isEmpty {
                                Text("• \(nextRoom)")
                                    .font(.system(.caption2, design: .default))
                                    .foregroundStyle(.secondary)
                            }
                            
                            if let nextStart = context.state.nextStartDate {
                                Spacer()
                                Text(formatTime(nextStart))
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                }
            } compactLeading: {
                LessonIcon(subject: context.state.subject)
                    .frame(width: 20, height: 20)
            } compactTrailing: {
                TimerView(
                    kind: context.state.kind,
                    startDate: context.state.startDate,
                    endDate: context.state.endDate,
                    nextStartDate: context.state.nextStartDate
                )
                .font(.system(.caption2, design: .rounded))
            } minimal: {
                LessonIcon(subject: context.state.subject)
                    .frame(width: 16, height: 16)
            }
        }
    }
    
    private func timeRange(context: ActivityViewContext<CurrentLessonActivityAttributes>) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: context.state.startDate))–\(formatter.string(from: context.state.endDate))"
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func shortenSubject(_ subject: String, maxLength: Int = 30) -> String {
        // Если название длиннее maxLength символов, обрезаем и добавляем "..."
        if subject.count > maxLength {
            return String(subject.prefix(maxLength - 3)) + "..."
        }
        return subject
    }
    
    private func formatRoom(_ room: String) -> String {
        // Форматируем аудиторию: "а. 2000" (максимум 8 символов)
        let trimmed = room.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 8 {
            return String(trimmed.prefix(8))
        }
        return trimmed
    }
}

// MARK: - Lock Screen View

@available(iOS 16.1, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<CurrentLessonActivityAttributes>
    
    var body: some View {
        VStack(spacing: 0) {
            // Текущая пара
            HStack(alignment: .top, spacing: 12) {
                // Иконка
                LessonIcon(subject: context.state.subject)
                    .frame(width: 36, height: 36)
                
                // Информация о текущей паре
                VStack(alignment: .leading, spacing: 6) {
                    // Название предмета
                    Text(shortenSubject(context.state.subject, maxLength: 35))
                        .font(.system(.headline, design: .default).weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .truncationMode(.tail)
                        .minimumScaleFactor(0.75)
                    
                    // Метаданные
                    HStack(spacing: 8) {
                        // Номер пары
                        HStack(spacing: 3) {
                            Image(systemName: "number.circle.fill")
                                .font(.system(.caption2))
                            Text("\(context.state.pairNumber)")
                                .font(.system(.caption, design: .default).weight(.medium))
                        }
                        .foregroundStyle(.blue)
                        
                        // Аудитория
                        if let room = context.state.room, !room.isEmpty {
                            HStack(spacing: 3) {
                                Image(systemName: "mappin.circle.fill")
                                    .font(.system(.caption2))
                                Text(room)
                                    .font(.system(.caption, design: .default))
                            }
                            .foregroundStyle(.secondary)
                        }
                        
                        // Время
                        HStack(spacing: 3) {
                            Image(systemName: "clock.fill")
                                .font(.system(.caption2))
                            Text(timeRange)
                                .font(.system(.caption, design: .monospaced))
                        }
                        .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)
            
            // Разделитель
            Divider()
                .padding(.horizontal, 16)
            
            // Следующая пара
            if let next = context.state.nextSubject, !next.isEmpty {
                HStack(alignment: .top, spacing: 12) {
                    // Иконка следующей пары
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.system(.title3))
                        .foregroundStyle(.green)
                        .frame(width: 36, height: 36)
                    
                    // Информация о следующей паре
                    VStack(alignment: .leading, spacing: 6) {
                        // Название предмета
                        Text(shortenSubject(next, maxLength: 35))
                            .font(.system(.subheadline, design: .default).weight(.medium))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                            .truncationMode(.tail)
                            .minimumScaleFactor(0.75)
                        
                        // Метаданные
                        HStack(spacing: 8) {
                            // Номер пары
                            if let nextNum = context.state.nextPairNumber {
                                HStack(spacing: 3) {
                                    Image(systemName: "number.circle.fill")
                                        .font(.system(.caption2))
                                    Text("\(nextNum)")
                                        .font(.system(.caption, design: .default).weight(.medium))
                                }
                                .foregroundStyle(.blue)
                            }
                            
                            // Аудитория
                            if let nextRoom = context.state.nextRoom, !nextRoom.isEmpty {
                                HStack(spacing: 3) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(.caption2))
                                    Text(nextRoom)
                                        .font(.system(.caption, design: .default))
                                }
                                .foregroundStyle(.secondary)
                            }
                            
                            // Время
                            if let nextStart = context.state.nextStartDate,
                               let nextEnd = context.state.nextEndDate {
                                HStack(spacing: 3) {
                                    Image(systemName: "clock.fill")
                                        .font(.system(.caption2))
                                    Text("\(formatTime(nextStart))–\(formatTime(nextEnd))")
                                        .font(.system(.caption, design: .monospaced))
                                }
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)
            }
        }
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        }
    }
    
    private var timeRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return "\(formatter.string(from: context.state.startDate))–\(formatter.string(from: context.state.endDate))"
    }
    
    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
    
    private func shortenSubject(_ subject: String, maxLength: Int = 30) -> String {
        // Если название длиннее maxLength символов, обрезаем и добавляем "..."
        if subject.count > maxLength {
            return String(subject.prefix(maxLength - 3)) + "..."
        }
        return subject
    }
}

// MARK: - Lesson Icon

private struct LessonIcon: View {
    let subject: String
    
    private var icon: String {
        let lower = subject.lowercased()
        if lower.contains("лекц") {
            return "book.closed.fill"
        } else if lower.contains("практ") {
            return "pencil.and.list.clipboard"
        } else if lower.contains("лаб") {
            return "flask.fill"
        } else {
            return "book.fill"
        }
    }
    
    private var color: Color {
        let lower = subject.lowercased()
        if lower.contains("лекц") {
            return .blue
        } else if lower.contains("практ") {
            return .green
        } else if lower.contains("лаб") {
            return .orange
        } else {
            return .purple
        }
    }
    
    var body: some View {
        ZStack {
            Circle()
                .fill(color.gradient)
            
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Next Event Time View

private struct TimerView: View {
    let kind: String
    let startDate: Date
    let endDate: Date
    let nextStartDate: Date?
    
    private var timeString: String {
        let targetDate: Date
        
        // Если пара идет сейчас (current), показываем время её конца
        // Если пара еще не началась (next), показываем время её начала
        if kind == "current" {
            targetDate = endDate
        } else {
            // kind == "next" - показываем начало следующей пары
            targetDate = startDate
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: targetDate)
    }
    
    var body: some View {
        Text(timeString)
            .contentTransition(.numericText())
            .lineLimit(1)
    }
}
