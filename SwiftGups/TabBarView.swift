//
//  TabBarView.swift
//  SwiftGups
//
//  Created by Assistant on 25.08.2025.
//

import SwiftUI
import SwiftData

struct TabBarView: View {
    let currentUser: User
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
    
    var body: some View {
        SwiftUI.Group {
            if isIPad {
                // iPad Layout - используем NavigationSplitView
                NavigationSplitView {
                    // Sidebar
                    List {
                        NavigationLink(destination: ScheduleTab(currentUser: currentUser, isInSplitView: true)) {
                            HStack(spacing: 12) {
                                Image(systemName: "calendar")
                                    .foregroundColor(.blue)
                                    .frame(width: 24, height: 24)
                                Text("Расписание")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color.clear)
                        
                        NavigationLink(destination: HomeworkTab(currentUser: currentUser, isInSplitView: true)) {
                            HStack(spacing: 12) {
                                Image(systemName: "book.closed")
                                    .foregroundColor(.green)
                                    .frame(width: 24, height: 24)
                                Text("Домашние задания")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color.clear)
                        
                        NavigationLink(destination: ProfileTab(currentUser: currentUser, isInSplitView: true)) {
                            HStack(spacing: 12) {
                                Image(systemName: "person.crop.circle")
                                    .foregroundColor(.purple)
                                    .frame(width: 24, height: 24)
                                Text("Профиль")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                Spacer()
                            }
                            .padding(.vertical, 8)
                        }
                        .listRowBackground(Color.clear)
                    }
                    .listStyle(SidebarListStyle())
                    .navigationTitle("SwiftGups")
                    .navigationBarTitleDisplayMode(.large)
                } detail: {
                    // По умолчанию показываем расписание
                    ScheduleTab(currentUser: currentUser, isInSplitView: true)
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                // iPhone Layout - обычный TabView
                TabView {
                    ScheduleTab(currentUser: currentUser, isInSplitView: false)
                        .tabItem {
                            Image(systemName: "calendar")
                            Text("Расписание")
                        }
                    
                    HomeworkTab(currentUser: currentUser, isInSplitView: false)
                        .tabItem {
                            Image(systemName: "book.closed")
                            Text("Домашние задания")
                        }
                    
                    ProfileTab(currentUser: currentUser, isInSplitView: false)
                        .tabItem {
                            Image(systemName: "person.crop.circle")
                            Text("Профиль")
                        }
                }
                .accentColor(.blue)
            }
        }
    }
}

// MARK: - Schedule Tab

struct ScheduleTab: View {
    let currentUser: User
    let isInSplitView: Bool
    @StateObject private var scheduleService = ScheduleService()
    @State private var showingLessonTimes = false
    
    var body: some View {
        SwiftUI.Group {
            if isInSplitView {
                // iPad layout - без NavigationView (уже в NavigationSplitView)
                VStack(spacing: 16) {
                    // Основной контент расписания
                    ContentView(scheduleService: scheduleService, showUserInfo: false)
                        .padding(.horizontal)
                }
                .navigationTitle("Расписание")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            showingLessonTimes = true
                        } label: {
                            Image(systemName: "clock")
                                .foregroundColor(.blue)
                        }
                    }
                }
            } else {
                // iPhone layout - с NavigationView
                NavigationView {
                    VStack(spacing: 12) {
                        // Основной контент расписания без повторного заголовка/юзер блока
                        ContentView(scheduleService: scheduleService, showUserInfo: false)
                            .padding(.horizontal)
                    }
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                showingLessonTimes = true
                            } label: {
                                Image(systemName: "clock")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingLessonTimes) {
            LessonTimesSheet()
        }
        .onAppear {
            // Автоматически выбираем факультет и группу пользователя
            setupScheduleForUser()
        }
    }
    
    private func setupScheduleForUser() {
        guard let faculty = Faculty.allFaculties.first(where: { $0.id == currentUser.facultyId }) else {
            print("❌ Faculty not found for user: \(currentUser.facultyId)")
            return
        }
        
        print("✅ Setting up schedule for user: \(currentUser.name), faculty: \(faculty.name), group: \(currentUser.groupId)")
        
        // Устанавливаем факультет напрямую без вызова selectFaculty (чтобы избежать двойной загрузки)
        scheduleService.selectedFaculty = faculty
        scheduleService.selectedGroup = nil
        scheduleService.currentSchedule = nil
        scheduleService.groups = []
        
        // Загружаем группы и затем выбираем нужную
        Task { @MainActor in
            print("🔄 Loading groups for faculty: \(faculty.id)")
            await scheduleService.loadGroups()
            
            print("📋 Loaded \(scheduleService.groups.count) groups")
            
            if let group = scheduleService.groups.first(where: { $0.id == currentUser.groupId }) {
                print("✅ Found user's group: \(group.name)")
                scheduleService.selectGroup(group)
            } else {
                print("⚠️ User's group not found in loaded groups. Available groups:")
                for group in scheduleService.groups.prefix(5) {
                    print("   - \(group.id): \(group.name)")
                }
                if let errorMessage = scheduleService.errorMessage {
                    print("❌ Error loading groups: \(errorMessage)")
                }
            }
        }
    }
}

struct UserInfoHeader: View {
    let user: User
    
    var body: some View {
        HStack(spacing: 12) {
            // Аватар пользователя
            Circle()
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 50, height: 50)
                .overlay(
                    Text(String(user.name.prefix(1)))
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 4) {
                Text("Привет, \(user.name)!")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("\(user.groupName), \(user.facultyName)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6))
        )
    }
}

struct LessonTimesSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Расписание звонков")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.horizontal)
                
                VStack(spacing: 12) {
                    ForEach(LessonTime.schedule) { lessonTime in
                        HStack {
                            Circle()
                                .fill(Color.blue)
                                .frame(width: 30, height: 30)
                                .overlay(
                                    Text("\(lessonTime.number)")
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("\(lessonTime.number) пара")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                
                                Text(lessonTime.timeRange)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                    }
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
    }
}

// MARK: - About Sheet

struct AboutSheet: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                Text("SwiftGups")
                    .font(.title2)
                    .fontWeight(.bold)
                    .padding(.top)
                    .padding(.horizontal)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Версия 1.0")
                    Text("Неформальное приложение для удобного просмотра расписания ДВГУПС.")
                        .foregroundColor(.secondary)
                    Text("Источник данных: dvgups.ru")
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.fraction(0.6), .large])
    }
}

// MARK: - Homework Tab

struct HomeworkTab: View {
    let currentUser: User
    let isInSplitView: Bool
    @Environment(\.modelContext) private var modelContext
    @Query private var homeworks: [Homework]
    @State private var showingAddHomework = false
    @State private var showingLessonTimes = false
    @State private var showingAbout = false
    @State private var selectedFilter: HomeworkFilter = .all
    
    private var filteredHomeworks: [Homework] {
        switch selectedFilter {
        case .all:
            return homeworks.sorted { $0.dueDate < $1.dueDate }
        case .pending:
            return homeworks.filter { !$0.isCompleted }.sorted { $0.dueDate < $1.dueDate }
        case .completed:
            return homeworks.filter { $0.isCompleted }.sorted { $0.updatedAt > $1.updatedAt }
        case .overdue:
            return homeworks.filter { !$0.isCompleted && $0.dueDate < Date() }.sorted { $0.dueDate < $1.dueDate }
        }
    }
    
    var body: some View {
        SwiftUI.Group {
            if isInSplitView {
                // iPad layout - без NavigationView
                VStack(spacing: 0) {
                    // Фильтры
                    HomeworkFilterBar(selectedFilter: $selectedFilter)
                        .padding()
                    
                    if filteredHomeworks.isEmpty {
                        EmptyHomeworkView(filter: selectedFilter)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List {
                            ForEach(filteredHomeworks) { homework in
                                HomeworkCard(homework: homework) {
                                    homework.toggle()
                                    try? modelContext.save()
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                .listRowSeparator(.hidden)
                            }
                            .onDelete(perform: deleteHomework)
                        }
                        .listStyle(PlainListStyle())
                    }
                }
                .navigationTitle("Домашние задания")
                .navigationBarTitleDisplayMode(.large)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        HStack {
                            Button {
                                showingLessonTimes = true
                            } label: {
                                Image(systemName: "clock")
                                    .foregroundColor(.blue)
                            }
                            
                            Button {
                                showingAbout = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .foregroundColor(.blue)
                            }
                            
                            Button {
                                showingAddHomework = true
                            } label: {
                                Image(systemName: "plus")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } else {
                // iPhone layout - с NavigationView
                NavigationView {
                    VStack(spacing: 0) {
                        // Фильтры
                        HomeworkFilterBar(selectedFilter: $selectedFilter)
                            .padding()
                        
                        if filteredHomeworks.isEmpty {
                            EmptyHomeworkView(filter: selectedFilter)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            List {
                                ForEach(filteredHomeworks) { homework in
                                    HomeworkCard(homework: homework) {
                                        homework.toggle()
                                        try? modelContext.save()
                                    }
                                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                                    .listRowSeparator(.hidden)
                                }
                                .onDelete(perform: deleteHomework)
                            }
                            .listStyle(PlainListStyle())
                        }
                    }
                    .navigationTitle("Домашние задания")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button {
                                showingAddHomework = true
                            } label: {
                                Image(systemName: "plus")
                                    .foregroundColor(.blue)
                            }
                        }
                        ToolbarItem(placement: .navigationBarLeading) {
                            Menu {
                                Button {
                                    showingLessonTimes = true
                                } label: {
                                    Label("Расписание звонков", systemImage: "clock")
                                }
                                Button {
                                    showingAbout = true
                                } label: {
                                    Label("О приложении", systemImage: "info.circle")
                                }
                            } label: {
                                Image(systemName: "ellipsis.circle")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddHomework) {
            AddHomeworkSheet()
        }
        .sheet(isPresented: $showingLessonTimes) {
            LessonTimesSheet()
        }
        .sheet(isPresented: $showingAbout) {
            AboutSheet()
        }
    }
    
    private func deleteHomework(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(filteredHomeworks[index])
            }
            try? modelContext.save()
        }
    }
}

enum HomeworkFilter: String, CaseIterable {
    case all = "Все"
    case pending = "К выполнению"
    case completed = "Выполненные"
    case overdue = "Просроченные"
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .pending: return "clock"
        case .completed: return "checkmark.circle"
        case .overdue: return "exclamationmark.triangle"
        }
    }
}

struct HomeworkFilterBar: View {
    @Binding var selectedFilter: HomeworkFilter
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(HomeworkFilter.allCases, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.icon)
                                .font(.caption)
                            
                            Text(filter.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(selectedFilter == filter ? Color.blue : Color(.systemGray6))
                        )
                        .foregroundColor(selectedFilter == filter ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}

struct HomeworkCard: View {
    let homework: Homework
    let toggleAction: () -> Void
    
    private var isOverdue: Bool {
        !homework.isCompleted && homework.dueDate < Date()
    }
    
    private var priorityColor: Color {
        switch homework.effectivePriority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(homework.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(homework.isCompleted ? .secondary : .primary)
                        .strikethrough(homework.isCompleted)
                    
                    Text(homework.subject)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toggleAction()
                    }
                }) {
                    Image(systemName: homework.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(homework.isCompleted ? .green : .gray)
                        .symbolEffect(.bounce, value: homework.isCompleted)
                }
            }
            
            if !homework.desc.isEmpty {
                Text(homework.desc)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            
            HStack {
                // Приоритет
                HStack(spacing: 4) {
                    Circle()
                        .fill(priorityColor)
                        .frame(width: 8, height: 8)
                    
                    Text(homework.effectivePriority.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Дата сдачи
                Text(homework.dueDate, format: .dateTime.day().month().year())
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isOverdue ? .red : .secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isOverdue ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
    }
}

struct EmptyHomeworkView: View {
    let filter: HomeworkFilter
    
    private var emptyMessage: String {
        switch filter {
        case .all:
            return "У вас пока нет домашних заданий"
        case .pending:
            return "Нет заданий к выполнению"
        case .completed:
            return "Нет выполненных заданий"
        case .overdue:
            return "Нет просроченных заданий"
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text(emptyMessage)
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if filter == .all {
                Text("Нажмите «+» чтобы добавить первое задание")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
    }
}

struct AddHomeworkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingHomeworks: [Homework]
    
    @State private var title = ""
    @State private var subject = ""
    @State private var description = ""
    @State private var dueDate = Date()
    @State private var priority = HomeworkPriority.medium
    @State private var suggestedSubjects: [String] = []
    @State private var showSuggestions = false
    @AppStorage("subjectPresets") private var subjectPresetsStorage: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Основная информация") {
                    TextField("Название задания", text: $title)
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Предмет", text: $subject)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: subject) { newValue in
                                updateSuggestions(for: newValue)
                            }
                            .onTapGesture {
                                if subject.isEmpty {
                                    updateSuggestions(for: "")
                                }
                            }
                        
                        if showSuggestions && !suggestedSubjects.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Предметы:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                                    ForEach(suggestedSubjects.prefix(8), id: \.self) { item in
                                        Button(action: { 
                                            subject = item
                                            showSuggestions = false
                                            // Haptic feedback
                                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                                            impactFeedback.impactOccurred()
                                        }) {
                                            HStack {
                                                Text(item)
                                                    .font(.subheadline)
                                                    .foregroundColor(.primary)
                                                Spacer()
                                                Image(systemName: "plus.circle.fill")
                                                    .foregroundColor(.blue)
                                                    .font(.caption)
                                            }
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 8)
                                            .background(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .fill(Color(.systemGray6))
                                                    .overlay(
                                                        RoundedRectangle(cornerRadius: 8)
                                                            .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                                    )
                                            )
                                        }
                                    }
                                }
                                
                                if suggestedSubjects.count > 8 {
                                    Text("И еще \(suggestedSubjects.count - 8) предметов...")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                }
                            }
                            .padding()
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color(.systemGray5).opacity(0.3))
                            )
                        }
                    }
                }
                
                Section("Описание") {
                    TextField("Описание задания", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Детали") {
                    DatePicker("Дата сдачи", selection: $dueDate, displayedComponents: [.date])
                    
                    Picker("Приоритет", selection: $priority) {
                        ForEach(HomeworkPriority.allCases, id: \.self) { priority in
                            Text(priority.rawValue).tag(priority)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
            }
            .navigationTitle("Новое задание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        saveHomework()
                    }
                    .fontWeight(.semibold)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
    
    private func saveHomework() {
        let homework = Homework(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: dueDate,
            priority: priority
        )
        
        modelContext.insert(homework)
        
        do {
            try modelContext.save()
            persistSubjectPreset()
            dismiss()
        } catch {
            print("Error saving homework: \(error)")
        }
    }

    private func updateSuggestions(for text: String) {
        // Получаем предметы из существующих домашних заданий
        let existingSubjects = Set(existingHomeworks.map { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty }
        
        // Получаем сохраненные предметы
        let stored = subjectPresetsStorage.split(separator: "|").map { String($0) }
        
        // Базовые предметы
        let baseDefaults: [String] = [
            "Математика","Физика","Информатика","Экономика","История",
            "Английский язык","Программирование","Сети","Алгоритмы",
            "Базы данных","Операционные системы","ОП ИИ"
        ]
        
        // Объединяем все источники предметов
        let allSubjects = Array(Set(Array(existingSubjects) + stored + baseDefaults))
            .filter { !$0.isEmpty }
            .sorted()
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            suggestedSubjects = allSubjects
            showSuggestions = true
        } else {
            suggestedSubjects = allSubjects.filter { $0.localizedCaseInsensitiveContains(trimmed) }
            showSuggestions = !suggestedSubjects.isEmpty
        }
    }

    private func persistSubjectPreset() {
        let value = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        var existing = Set(subjectPresetsStorage.split(separator: "|").map { String($0) })
        existing.insert(value)
        subjectPresetsStorage = existing.sorted().joined(separator: "|")
    }
}

// MARK: - Profile Tab

struct ProfileTab: View {
    let currentUser: User
    let isInSplitView: Bool
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var cloudKitService: CloudKitService
    @State private var showingEditProfile = false
    @State private var showingDeleteConfirmation = false
    @State private var showingLessonTimes = false
    @State private var showingAbout = false
    
    var body: some View {
        SwiftUI.Group {
            if isInSplitView {
                // iPad layout - без NavigationView
                ScrollView {
                    VStack(spacing: 24) {
                        // Профиль пользователя
                        ProfileHeader(user: currentUser)
                            .padding(.top)
                        
                        // Статус синхронизации
                        CloudKitStatusView(cloudKitService: cloudKitService)
                            .padding(.horizontal)
                        
                        // Настройки
                        VStack(spacing: 16) {
                            ProfileMenuItem(
                                title: "Редактировать профиль",
                                icon: "person.crop.circle",
                                action: { showingEditProfile = true }
                            )
                            
                            ProfileMenuItem(
                                title: "Расписание звонков",
                                icon: "clock",
                                action: { showingLessonTimes = true }
                            )
                            
                            ProfileMenuItem(
                                title: "О приложении",
                                icon: "info.circle",
                                action: { showingAbout = true }
                            )
                            
                            Divider()
                                .padding(.vertical)
                            
                            ProfileMenuItem(
                                title: "Сбросить данные",
                                icon: "trash",
                                isDestructive: true,
                                action: { showingDeleteConfirmation = true }
                            )
                        }
                        .padding(.horizontal)
                        
                        Spacer()
                    }
                }
                .navigationTitle("Профиль")
                .navigationBarTitleDisplayMode(.large)
            } else {
                // iPhone layout - с NavigationView
                NavigationView {
                    ScrollView {
                        VStack(spacing: 24) {
                            // Профиль пользователя
                            ProfileHeader(user: currentUser)
                                .padding(.top)
                            
                            // Статус синхронизации
                            CloudKitStatusView(cloudKitService: cloudKitService)
                                .padding(.horizontal)
                            
                            // Настройки
                            VStack(spacing: 16) {
                                ProfileMenuItem(
                                    title: "Редактировать профиль",
                                    icon: "person.crop.circle",
                                    action: { showingEditProfile = true }
                                )
                                
                                ProfileMenuItem(
                                    title: "Расписание звонков",
                                    icon: "clock",
                                    action: { showingLessonTimes = true }
                                )
                                
                                ProfileMenuItem(
                                    title: "О приложении",
                                    icon: "info.circle",
                                    action: { showingAbout = true }
                                )
                                
                                Divider()
                                    .padding(.vertical)
                                
                                ProfileMenuItem(
                                    title: "Сбросить данные",
                                    icon: "trash",
                                    isDestructive: true,
                                    action: { showingDeleteConfirmation = true }
                                )
                            }
                            .padding(.horizontal)
                            
                            Spacer()
                        }
                    }
                    .navigationTitle("Профиль")
                    .navigationBarTitleDisplayMode(.large)
                }
            }
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileSheet(user: currentUser)
        }
        .sheet(isPresented: $showingLessonTimes) {
            LessonTimesSheet()
        }
        .sheet(isPresented: $showingAbout) {
            AboutSheet()
        }
        .confirmationDialog(
            "Сбросить все данные?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Сбросить данные", role: .destructive) {
                resetUserData()
            }
            
            Button("Отмена", role: .cancel) { }
        } message: {
            Text("Все ваши данные будут удалены. Это действие нельзя отменить.")
        }
    }
    
    private func resetUserData() {
        modelContext.delete(currentUser)
        try? modelContext.save()
    }
}

struct ProfileHeader: View {
    let user: User
    
    var body: some View {
        VStack(spacing: 16) {
            // Аватар
            Circle()
                .fill(LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 100, height: 100)
                .overlay(
                    Text(String(user.name.prefix(1)))
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(.white)
                )
                .shadow(color: .blue.opacity(0.3), radius: 10, x: 0, y: 5)
            
            VStack(spacing: 8) {
                Text(user.name)
                    .font(.title2)
                    .fontWeight(.bold)
                
                Text(user.groupName)
                    .font(.headline)
                    .foregroundColor(.blue)
                
                Text(user.facultyName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemGray6).opacity(0.5))
        )
        .padding(.horizontal)
    }
}

struct ProfileMenuItem: View {
    let title: String
    let icon: String
    let isDestructive: Bool
    let action: () -> Void
    
    init(title: String, icon: String, isDestructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.isDestructive = isDestructive
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(isDestructive ? .red : .blue)
                    .frame(width: 24)
                
                Text(title)
                    .font(.body)
                    .foregroundColor(isDestructive ? .red : .primary)
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
    }
}

struct EditProfileSheet: View {
    let user: User
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name: String
    @State private var selectedFaculty: Faculty?
    @State private var selectedGroup: Group?
    @StateObject private var scheduleService = ScheduleService()
    
    init(user: User) {
        self.user = user
        _name = State(initialValue: user.name)
        _selectedFaculty = State(initialValue: Faculty.allFaculties.first { $0.id == user.facultyId })
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section("Личная информация") {
                    TextField("Имя", text: $name)
                }
                
                Section("Учебная информация") {
                    VStack(alignment: .leading) {
                        Text("Институт/Факультет")
                        Picker("Институт/Факультет", selection: $selectedFaculty) {
                            Text("Выберите факультет").tag(nil as Faculty?)
                            ForEach(Faculty.allFaculties) { faculty in
                                Text(faculty.name).tag(faculty as Faculty?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                    }
                }
                
                if selectedFaculty != nil {
                    Section("Выбор группы") {
                        VStack(alignment: .leading) {
                            Text("Группа")
                            Picker("Группа", selection: $selectedGroup) {
                                Text("Выберите группу").tag(nil as Group?)
                                ForEach(scheduleService.groups) { group in
                                    Text("\(group.name) - \(group.fullName)").tag(group as Group?)
                                }
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                        }
                    }
                }
            }
            .navigationTitle("Редактировать профиль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
            .onChange(of: selectedFaculty) { newFaculty in
                if let faculty = newFaculty {
                    scheduleService.selectFaculty(faculty)
                    selectedGroup = nil
                }
            }
        }
        .task {
            if let faculty = selectedFaculty {
                scheduleService.selectFaculty(faculty)
                await scheduleService.loadGroups()
                selectedGroup = scheduleService.groups.first { $0.id == user.groupId }
            }
        }
    }
    
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedFaculty != nil &&
        selectedGroup != nil
    }
    
    private func saveChanges() {
        guard let faculty = selectedFaculty,
              let group = selectedGroup else { return }
        
        user.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        user.updateFaculty(facultyId: faculty.id, facultyName: faculty.name)
        user.updateGroup(groupId: group.id, groupName: group.name)
        
        do {
            try modelContext.save()
            dismiss()
        } catch {
            print("Error saving user: \(error)")
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: User.self, Homework.self, configurations: config)

    let sampleUser = User(name: "Иван Иванов", facultyId: "2", facultyName: "Институт управления", groupId: "58031", groupName: "БО241ИСТ")
    container.mainContext.insert(sampleUser)

    return TabBarView(currentUser: sampleUser)
        .modelContainer(container)
}
