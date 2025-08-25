import SwiftUI

struct ContentView: View {
    @StateObject private var scheduleService: ScheduleService
    @State private var searchText = ""
    @State private var showDatePicker = false
    let showUserInfo: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    init(scheduleService: ScheduleService? = nil, showUserInfo: Bool = true) {
        self._scheduleService = StateObject(wrappedValue: scheduleService ?? ScheduleService())
        self.showUserInfo = showUserInfo
    }

    var body: some View {
        Group {
            if isIPad && !showUserInfo {
                // iPad расписание без NavigationView (для использования в NavigationSplitView)
                ScrollView {
                    LazyVStack(spacing: 24) {
                        // Выбор даты - больше и компактнее для iPad
                        DateSelectionView(scheduleService: scheduleService, showDatePicker: $showDatePicker)
                            .padding(.horizontal, 24)
                        
                        // Отображение расписания - с большими отступами
                        ScheduleDisplayView(scheduleService: scheduleService)
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 16)
                }
                .refreshable {
                    await scheduleService.refresh()
                }
            } else {
                // iPhone или standalone версия
                NavigationView {
                    ScrollView {
                        VStack(spacing: isIPad ? 24 : 20) {
                            // Заголовок (только для standalone версии)
                            if showUserInfo {
                                HeaderView()
                            }
                            
                            // Выбор факультета
                            if showUserInfo {
                                FacultySelectionView(scheduleService: scheduleService)
                            }
                            
                            // Выбор даты
                            DateSelectionView(scheduleService: scheduleService, showDatePicker: $showDatePicker)
                            
                            // Поиск и выбор группы
                            if scheduleService.selectedFaculty != nil && showUserInfo {
                                GroupSelectionView(scheduleService: scheduleService, searchText: $searchText)
                            }
                            
                            // Отображение расписания
                            ScheduleDisplayView(scheduleService: scheduleService)
                            
                            Spacer(minLength: 40)
                        }
                        .padding(.horizontal, isIPad ? 24 : 16)
                        .padding(.vertical, isIPad ? 20 : 16)
                    }
                    .navigationTitle(showUserInfo ? "SwiftGups" : "")
                    .navigationBarTitleDisplayMode(showUserInfo ? .large : .inline)
                    .refreshable {
                        if showUserInfo {
                            await scheduleService.refresh()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showDatePicker) {
            DatePickerSheet(selectedDate: $scheduleService.selectedDate) {
                scheduleService.selectDate(scheduleService.selectedDate)
            }
        }
        .task {
            // В standalone режиме подгружаем группы автоматически, встраиваемый режим (в табе) управляется снаружи
            if showUserInfo, scheduleService.selectedFaculty != nil {
                await scheduleService.loadGroups()
            }
        }
    }
}

// MARK: - Header View

struct HeaderView: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("🎓")
                .font(.system(size: 50))
            
            Text("Расписание ДВГУПС")
                .font(.title2)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
            
            Text("Удобный просмотр расписания занятий")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Faculty Selection View

struct FacultySelectionView: View {
    @ObservedObject var scheduleService: ScheduleService

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Институт/Факультет", systemImage: "building.2")
                .font(.headline)
                .foregroundColor(.primary)
            
            Menu {
                ForEach(scheduleService.faculties) { faculty in
                    Button(action: {
                        scheduleService.selectFaculty(faculty)
                    }) {
                        HStack {
                            Text(faculty.name)
                            if scheduleService.selectedFaculty?.id == faculty.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(scheduleService.selectedFaculty?.name ?? "Выберите институт/факультет")
                        .foregroundColor(scheduleService.selectedFaculty != nil ? .primary : .secondary)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Date Selection View

struct DateSelectionView: View {
    @ObservedObject var scheduleService: ScheduleService
    @Binding var showDatePicker: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Неделя", systemImage: "calendar")
                .font(.headline)
                .foregroundColor(.primary)
            
            // Навигация по неделям
            HStack(spacing: 12) {
                // Предыдущая неделя
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scheduleService.previousWeek()
                    }
                }) {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 0.1), value: scheduleService.selectedDate)
                }
                
                Spacer()
                
                // Текущая неделя
                VStack(spacing: 4) {
                    Text(scheduleService.currentWeekRange())
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Button("Текущая неделя") {
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                        
                        withAnimation(.easeInOut(duration: 0.3)) {
                            scheduleService.goToCurrentWeek()
                        }
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
                
                Spacer()
                
                // Следующая неделя
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                    impactFeedback.impactOccurred()
                    
                    withAnimation(.easeInOut(duration: 0.3)) {
                        scheduleService.nextWeek()
                    }
                }) {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 0.1), value: scheduleService.selectedDate)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )
            
            // Кнопка выбора конкретной даты
            Button(action: {
                showDatePicker = true
            }) {
                HStack {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundColor(.blue)
                    
                    Text("Выбрать дату")
                        .foregroundColor(.primary)
                    
                    Spacer()
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Group Selection View

struct GroupSelectionView: View {
    @ObservedObject var scheduleService: ScheduleService
    @Binding var searchText: String
    
    private var filteredGroups: [Group] {
        scheduleService.filteredGroups(searchText: searchText)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Группа", systemImage: "person.3")
                .font(.headline)
                .foregroundColor(.primary)
            
            // Поле поиска
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                
                TextField("Поиск группы...", text: $searchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                
                if !searchText.isEmpty {
                    Button("Очистить") {
                        searchText = ""
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal)
            
            if scheduleService.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Загрузка групп...")
                        .progressViewStyle(CircularProgressViewStyle())
                    Spacer()
                }
                .padding()
            } else if filteredGroups.isEmpty && scheduleService.selectedFaculty != nil {
                Text("Группы не найдены")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 12) {
                        ForEach(filteredGroups) { group in
                            GroupCard(
                                group: group,
                                isSelected: scheduleService.selectedGroup?.id == group.id
                            ) {
                                scheduleService.selectGroup(group)
                                searchText = "" // Очищаем поиск после выбора
                            }
                        }
                    }
                    .padding(.horizontal)
                }
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Group Card

struct GroupCard: View {
    let group: Group
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(group.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : .primary)
                
                Text(group.fullName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
            }
            .padding()
            .frame(width: 180, height: 80)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
        }
    }
}

// MARK: - Schedule Display View

struct ScheduleDisplayView: View {
    @ObservedObject var scheduleService: ScheduleService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let errorMessage = scheduleService.errorMessage {
                ErrorView(message: errorMessage) {
                    scheduleService.errorMessage = nil
                }
            }
            
            if scheduleService.isLoading {
                LoadingView()
            } else if let schedule = scheduleService.currentSchedule {
                ScheduleView(schedule: schedule)
            } else if scheduleService.selectedGroup != nil {
                EmptyScheduleView()
            }
        }
    }
}

// MARK: - Error View

struct ErrorView: View {
    let message: String
    let dismissAction: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundColor(.red)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
            
            Spacer()
            
            Button("OK", action: dismissAction)
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.red.opacity(0.1))
                .stroke(Color.red.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Loading View

struct LoadingView: View {
    var body: some View {
        HStack {
            Spacer()
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle())
                    .scaleEffect(1.2)
                
                Text("Загрузка расписания...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(40)
    }
}

// MARK: - Empty Schedule View

struct EmptyScheduleView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 50))
                .foregroundColor(.gray)
            
            Text("Расписание не найдено")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("На выбранную дату расписание отсутствует")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(40)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Schedule View

struct ScheduleView: View {
    let schedule: Schedule
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Заголовок расписания
            VStack(alignment: .leading, spacing: 8) {
                Text("Расписание")
                    .font(isIPad ? .title : .title2)
                    .fontWeight(.bold)
                
                Text(schedule.groupName)
                    .font(isIPad ? .title3 : .headline)
                    .foregroundColor(.blue)
                
                Text("Период: \(DateFormatter.displayDateFormatter.string(from: schedule.startDate)) - \(DateFormatter.displayDateFormatter.string(from: schedule.endDate))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Дни расписания
            if schedule.days.isEmpty {
                EmptyScheduleView()
            } else {
                if isIPad && schedule.days.count > 2 {
                    // iPad: сетка 2x2 или 3x2 для компактного отображения
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 2), spacing: 16) {
                        ForEach(schedule.days) { day in
                            ScheduleDayView(day: day, isCompact: true)
                        }
                    }
                } else {
                    // iPhone: вертикальный список
                    LazyVStack(spacing: 16) {
                        ForEach(schedule.days) { day in
                            ScheduleDayView(day: day, isCompact: false)
                        }
                    }
                }
            }
        }
        .padding(isIPad ? 20 : 16)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
        )
    }
}

// MARK: - Schedule Day View

struct ScheduleDayView: View {
    let day: ScheduleDay
    let isCompact: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Заголовок дня
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(day.weekday)
                        .font(.headline)
                        .fontWeight(.semibold)
                    
                    Text(DateFormatter.apiDateFormatter.string(from: day.date))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let weekNumber = day.weekNumber {
                    Text("\(weekNumber)-я неделя")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill((day.isEvenWeek ?? false) ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                        )
                        .foregroundColor((day.isEvenWeek ?? false) ? .green : .orange)
                }
            }
            
            // Занятия
            if day.lessons.isEmpty {
                Text("Нет занятий")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .padding()
            } else {
                if isCompact && day.lessons.count > 3 {
                    // Компактное отображение для iPad - показываем только первые 2 занятия + счетчик
                    LazyVStack(spacing: 6) {
                        ForEach(day.lessons.prefix(2)) { lesson in
                            LessonView(lesson: lesson, isCompact: true)
                        }
                        if day.lessons.count > 2 {
                            Text("ещё \(day.lessons.count - 2)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        }
                    }
                } else {
                    LazyVStack(spacing: isCompact ? 6 : 8) {
                        ForEach(day.lessons) { lesson in
                            LessonView(lesson: lesson, isCompact: isCompact)
                        }
                    }
                }
            }
        }
        .padding(isIPad && isCompact ? 12 : 16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// MARK: - Lesson View

struct LessonView: View {
    let lesson: Lesson
    let isCompact: Bool
    
    private var lessonTypeColor: Color {
        switch lesson.type {
        case .lecture:
            return .blue
        case .practice:
            return .green
        case .laboratory:
            return .orange
        case .unknown:
            return .gray
        }
    }
    
    var body: some View {
        if isCompact {
            // Компактное отображение для iPad
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("\(lesson.pairNumber)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(lessonTypeColor)
                        .frame(width: 20)
                    
                    if lesson.subject.containsURL {
                        ClickableLinkText(text: lesson.subject)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    } else {
                        Text(lesson.subject)
                            .font(.caption)
                            .fontWeight(.medium)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
                
                HStack(spacing: 6) {
                    Text("\(lesson.timeStart)-\(lesson.timeEnd)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    if let room = lesson.room, !room.isEmpty {
                        Text("📍 \(room)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Spacer()
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(lessonTypeColor.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(lessonTypeColor.opacity(0.3), lineWidth: 1)
                    )
            )
        } else {
            // Полное отображение для iPhone
            HStack(alignment: .top, spacing: 12) {
                // Номер пары и время
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(lesson.pairNumber) пара")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(lessonTypeColor)
                    
                    Text("\(lesson.timeStart)-\(lesson.timeEnd)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .frame(width: 60, alignment: .leading)
                
                // Информация о занятии
                VStack(alignment: .leading, spacing: 4) {
                    // Предмет
                    if lesson.subject.containsURL {
                        ClickableLinkText(text: lesson.subject)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                    } else {
                        Text(lesson.subject)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .lineLimit(2)
                    }
                    
                    // Тип занятия
                    Text(lesson.type.rawValue)
                        .font(.caption)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(lessonTypeColor.opacity(0.2))
                        )
                        .foregroundColor(lessonTypeColor)
                    
                    // Преподаватель
                    if let teacher = lesson.teacher, !teacher.name.isEmpty {
                        HStack(spacing: 4) {
                            if teacher.name.containsURL {
                                // Если имя преподавателя содержит ссылку
                                ClickableLinkText(text: teacher.name)
                                    .font(.caption)
                            } else {
                                Text(teacher.name)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if let email = teacher.email, !email.isEmpty {
                                Link("✉️", destination: URL(string: "mailto:\(email)") ?? URL(string: "about:blank")!)
                                    .font(.caption2)
                            }
                        }
                    }
                    
                    // Аудитория
                    if let room = lesson.room, !room.isEmpty {
                        if room.containsURL {
                            ClickableLinkText(text: "📍 \(room)")
                                .font(.caption)
                        } else {
                            Text("📍 \(room)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Онлайн информация
                    if let onlineLink = lesson.onlineLink, !onlineLink.isEmpty {
                        if onlineLink.containsURL {
                            ClickableLinkText(text: "💻 \(onlineLink)")
                                .font(.caption)
                        } else {
                            Text("💻 \(onlineLink)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
            )
        }
    }
}

// MARK: - Date Picker Sheet

struct DatePickerSheet: View {
    @Binding var selectedDate: Date
    let onDateSelected: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Выберите дату")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.top)
                
                DatePicker(
                    "Дата",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(GraphicalDatePickerStyle())
                .padding()
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        onDateSelected()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.fraction(0.7), .large])
    }
}

// MARK: - Clickable Link Text Component

struct ClickableLinkText: View {
    let text: String
    
    var body: some View {
        let urls = text.extractedURLs
        
        if urls.isEmpty {
            // Если нет URL, отображаем как обычный текст
            Text(text)
                .foregroundColor(.secondary)
        } else if urls.count == 1, let url = urls.first, text.trimmingCharacters(in: .whitespacesAndNewlines) == url.absoluteString {
            // Если весь текст - это одна ссылка
            Link(text, destination: url)
                .foregroundColor(.blue)
        } else {
            // Если текст содержит ссылки среди обычного текста
            HStack(alignment: .top, spacing: 4) {
                // Разбиваем текст на части и создаем отдельные элементы для ссылок и текста
                let parts = parseTextWithLinks(text)
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    if let url = URL(string: part), urls.contains(where: { $0.absoluteString == part }) {
                        Link(part, destination: url)
                            .foregroundColor(.blue)
                            .underline()
                    } else {
                        Text(part)
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
    }
    
    private func parseTextWithLinks(_ text: String) -> [String] {
        let urls = text.extractedURLs.map { $0.absoluteString }
        var result: [String] = []
        var remainingText = text
        
        for url in urls {
            let components = remainingText.components(separatedBy: url)
            if let first = components.first {
                if !first.isEmpty {
                    result.append(first)
                }
                result.append(url)
                remainingText = components.dropFirst().joined(separator: url)
            }
        }
        
        if !remainingText.isEmpty {
            result.append(remainingText)
        }
        
        return result.filter { !$0.isEmpty }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}