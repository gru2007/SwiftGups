//
//  TabBarView.swift
//  SwiftGups
//
//  Created by Assistant on 25.08.2025.
//

import SwiftUI
import SwiftData

enum AppTab: String, CaseIterable, Hashable {
    case schedule = "schedule"
    case homework = "homework"
    case news = "news"
    case connect = "connect"
    case profile = "profile"
    
    var title: String {
        switch self {
        case .schedule: return "Расписание"
        case .homework: return "Домашние задания"
        case .news: return "Новости"
        case .connect: return "Connect"
        case .profile: return "Профиль"
        }
    }
    
    var icon: String {
        switch self {
        case .schedule: return "calendar"
        case .homework: return "book.closed"
        case .news: return "newspaper"
        case .connect: return "link.circle"
        case .profile: return "person.crop.circle"
        }
    }
    
    var color: Color {
        switch self {
        case .schedule: return .blue
        case .homework: return .green
        case .news: return .orange
        case .connect: return .cyan
        case .profile: return .purple
        }
    }
}

struct TabBarView: View {
    let currentUser: User
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var selectedTab: AppTab = .schedule
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular && verticalSizeClass == .regular
    }
    
    var body: some View {
        SwiftUI.Group {
            if isIPad {
                // iPad Layout - используем NavigationSplitView с selection
                NavigationSplitView {
                    // Sidebar
                    List {
                        ForEach(AppTab.allCases, id: \.self) { tab in
                            Button(action: {
                                selectedTab = tab
                            }) {
                                HStack(spacing: 16) {
                                    Image(systemName: tab.icon)
                                        .foregroundColor(selectedTab == tab ? tab.color : .gray)
                                        .frame(width: 28, height: 28)
                                        .font(.title3)
                                    
                                    Text(tab.title)
                                        .font(.headline)
                                        .foregroundColor(selectedTab == tab ? tab.color : .primary)
                                    
                                    Spacer()
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(selectedTab == tab ? tab.color.opacity(0.1) : Color.clear)
                                )
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(PlainButtonStyle())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        }
                    }
                    .listStyle(SidebarListStyle())
                    .navigationTitle("SwiftGups")
                    .navigationBarTitleDisplayMode(.large)
                    .environment(\.defaultMinListRowHeight, 60)
                } detail: {
                    // Отображаем выбранную вкладку
                    selectedTabView
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                // iPhone Layout - обычный TabView
                TabView {
                    ScheduleTab(currentUser: currentUser, isInSplitView: false)
                        .tabItem {
                            Image(systemName: "calendar")
                            Text("Пары")
                        }
                    
                    HomeworkTab(currentUser: currentUser, isInSplitView: false)
                        .tabItem {
                            Image(systemName: "book.closed")
                            Text("Домашка")
                        }
                    
                    NewsTab(isInSplitView: false)
                        .tabItem {
                            Image(systemName: "newspaper")
                            Text("Новости")
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
    
    @ViewBuilder
    private var selectedTabView: some View {
        switch selectedTab {
        case .schedule:
            ScheduleTab(currentUser: currentUser, isInSplitView: true)
        case .homework:
            HomeworkTab(currentUser: currentUser, isInSplitView: true)
        case .news:
            NewsTab(isInSplitView: true)
        case .connect:
            ConnectTab(currentUser: currentUser, isInSplitView: true)
        case .profile:
            ProfileTab(currentUser: currentUser, isInSplitView: true)
        }
    }
}

// MARK: - Schedule Tab

struct ScheduleTab: View {
    let currentUser: User
    let isInSplitView: Bool
    @StateObject private var scheduleService = ScheduleService()
    @State private var showingLessonTimes = false

    // Проверяем, указал ли пользователь группу
    private var hasGroup: Bool { !currentUser.groupId.isEmpty }
    
    var body: some View {
        SwiftUI.Group {
            if !hasGroup {
                // Сообщение, если группа не выбрана
                VStack(spacing: 16) {
                    Text("Группа не выбрана")
                        .font(.headline)

                    Text("Откройте вкладку «Профиль» и укажите группу, чтобы просматривать расписание.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            } else if isInSplitView {
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
            guard hasGroup else { return }
            Task { @MainActor in
                await setupScheduleForUser()
            }
        }
    }
    
    private func setupScheduleForUser() async {
        guard hasGroup else {
            print("⚠️ У пользователя не выбрана группа, расписание не загружается")
            return
        }

        await scheduleService.ensureFacultiesLoaded()
        
        guard let faculty =
                scheduleService.faculties.first(where: { $0.id == currentUser.facultyId }) ??
                Faculty.allFaculties.first(where: { $0.id == currentUser.facultyId }) else {
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
                    Text("Неофициальное приложение по ДВГУПС. Создано с ❤️ и SwiftUI.")
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
    @State private var selectedSubject: String = "Все предметы"
    @State private var homeworkToEdit: Homework? = nil
    @AppStorage("homeworkDeprecationDismissed") private var homeworkDeprecationDismissed: Bool = false
    
    // Все уникальные предметы для фильтрации
    private var availableSubjects: [String] {
        let subjects = Set(homeworks.map { $0.subject })
        return (["Все предметы"] + subjects.sorted()).filter { !$0.isEmpty }
    }
    
    private var filteredHomeworks: [Homework] {
        let filtered = homeworks.filter { homework in
            // Фильтр по статусу
            let statusMatch = switch selectedFilter {
            case .all: true
            case .completed: homework.isCompleted
            case .pending: !homework.isCompleted
            case .overdue: !homework.isCompleted && homework.dueDate < Date()
            }
            
            // Фильтр по предмету
            let subjectMatch = selectedSubject == "Все предметы" || homework.subject == selectedSubject
            
            return statusMatch && subjectMatch
        }
        
        return filtered.sorted { (lhs: Homework, rhs: Homework) in
            // Просроченные задания в начале
            let lhsOverdue = !lhs.isCompleted && lhs.dueDate < Date()
            let rhsOverdue = !rhs.isCompleted && rhs.dueDate < Date()
            
            if lhsOverdue && !rhsOverdue {
                return true
            } else if !lhsOverdue && rhsOverdue {
                return false
            }
            
            // Остальные сортируем по дате сдачи
            return lhs.dueDate < rhs.dueDate
        }
    }
    
    var body: some View {
        SwiftUI.Group {
            if isInSplitView {
                // iPad layout - без NavigationView
                VStack(spacing: 0) {
                    // Депрекейшн баннер
                    if !homeworkDeprecationDismissed {
                        HomeworkDeprecationBanner {
                            homeworkDeprecationDismissed = true
                        }
                        .padding([.top, .horizontal])
                    }
                    
                    // Фильтры
                    VStack(spacing: 12) {
                        HomeworkFilterBar(selectedFilter: $selectedFilter)
                        
                        // Фильтр по предметам
                        if !availableSubjects.isEmpty {
                            HStack {
                                Text("Предмет:")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                                
                                Menu {
                                    ForEach(availableSubjects, id: \.self) { subject in
                                        Button(subject) {
                                            selectedSubject = subject
                                        }
                                    }
                                } label: {
                                    HStack {
                                        Text(selectedSubject)
                                            .font(.subheadline)
                                            .foregroundColor(.primary)
                                        
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(Color(.systemGray6))
                                    .cornerRadius(8)
                                }
                            }
                            .padding(.horizontal)
                        }
                    }
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
                                .contextMenu {
                                    Button {
                                        homeworkToEdit = homework
                                    } label: {
                                        Label("Редактировать", systemImage: "pencil")
                                    }
                                    
                                    Button {
                                        homework.toggle()
                                        try? modelContext.save()
                                    } label: {
                                        Label(homework.isCompleted ? "Отменить выполнение" : "Отметить выполненным", 
                                              systemImage: homework.isCompleted ? "circle" : "checkmark.circle")
                                    }
                                    
                                    Divider()
                                    
                                    Button(role: .destructive) {
                                        modelContext.delete(homework)
                                        try? modelContext.save()
                                    } label: {
                                        Label("Удалить", systemImage: "trash")
                                    }
                                }
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
                        // Депрекейшн баннер
                        if !homeworkDeprecationDismissed {
                            HomeworkDeprecationBanner {
                                homeworkDeprecationDismissed = true
                            }
                            .padding([.top, .horizontal])
                        }
                        
                        // Фильтры
                        VStack(spacing: 12) {
                            HomeworkFilterBar(selectedFilter: $selectedFilter)
                            
                            // Фильтр по предметам
                            if !availableSubjects.isEmpty {
                                HStack {
                                    Text("Предмет:")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    
                                    Spacer()
                                    
                                    Menu {
                                        ForEach(availableSubjects, id: \.self) { subject in
                                            Button(subject) {
                                                selectedSubject = subject
                                            }
                                        }
                                    } label: {
                                        HStack {
                                            Text(selectedSubject)
                                                .font(.subheadline)
                                                .foregroundColor(.primary)
                                            
                                            Image(systemName: "chevron.down")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(Color(.systemGray6))
                                        .cornerRadius(8)
                                    }
                                }
                                .padding(.horizontal)
                            }
                        }
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
                                    .contextMenu {
                                        Button {
                                            homeworkToEdit = homework
                                        } label: {
                                            Label("Редактировать", systemImage: "pencil")
                                        }
                                        
                                        Button {
                                            homework.toggle()
                                            try? modelContext.save()
                                        } label: {
                                            Label(homework.isCompleted ? "Отменить выполнение" : "Отметить выполненным", 
                                                  systemImage: homework.isCompleted ? "circle" : "checkmark.circle")
                                        }
                                        
                                        Divider()
                                        
                                        Button(role: .destructive) {
                                            modelContext.delete(homework)
                                            try? modelContext.save()
                                        } label: {
                                            Label("Удалить", systemImage: "trash")
                                        }
                                    }
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
        .sheet(item: $homeworkToEdit) { homework in
            EditHomeworkSheet(homework: homework)
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
    @State private var showingPhotos = false
    
    private var isOverdue: Bool {
        !homework.isCompleted && homework.dueDate < Date()
    }
    
    private var priorityColor: Color {
        switch homework.priority {
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
                .buttonStyle(PlainButtonStyle())  // Явно задаем стиль кнопки
                .frame(width: 44, height: 44)     // Увеличиваем зону нажатия
            }
            
            if !homework.desc.isEmpty {
                Text(homework.desc)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            
            // Миниатюры фотографий (если есть)
            if !homework.imageAttachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(homework.imageAttachments.prefix(3), id: \.self) { attachment in
                            Button {
                                showingPhotos = true
                            } label: {
                                if let image = AttachmentManager.shared.loadImage(attachment) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 60, height: 40)
                                        .clipped()
                                        .cornerRadius(8)
                                } else {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.3))
                                        .frame(width: 60, height: 40)
                                        .cornerRadius(8)
                                        .overlay(
                                            Image(systemName: "photo")
                                                .foregroundColor(.gray)
                                        )
                                }
                            }
                        }
                        
                        // Показать "+X" если фотографий больше 3
                        if homework.imageAttachments.count > 3 {
                            Button {
                                showingPhotos = true
                            } label: {
                                Rectangle()
                                    .fill(Color.blue.opacity(0.1))
                                    .frame(width: 60, height: 40)
                                    .cornerRadius(8)
                                    .overlay(
                                        Text("+\(homework.imageAttachments.count - 3)")
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .foregroundColor(.blue)
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
            
            HStack {
                // Приоритет
                HStack(spacing: 4) {
                    Circle()
                        .fill(priorityColor)
                        .frame(width: 8, height: 8)
                    
                    Text(homework.priority.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Иконка фотографий (если есть)
                if !homework.imageAttachments.isEmpty {
                    Button {
                        showingPhotos = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundColor(.blue)
                            
                            Text("\(homework.imageAttachments.count)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
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
        .sheet(isPresented: $showingPhotos) {
            HomeworkPhotosSheet(homework: homework)
        }
    }
}

// MARK: - Homework Deprecation Banner

struct HomeworkDeprecationBanner: View {
    @Environment(\.openURL) private var openURL
    let dismissAction: () -> Void
    
    init(dismissAction: @escaping () -> Void) {
        self.dismissAction = dismissAction
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundColor(.orange)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("Функция скоро будет обновлена")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    
                    Text("Совместно со студсоветом ведём разработку улучшенной кроссплатформенной версии (iOS/Android). Если вы активно используете «Домашние задания», дайте знать в Telegram.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    
                    HStack(spacing: 12) {
                        Button {
                            if let url = URL(string: "https://artemevkhv.t.me") {
                                openURL(url)
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "paperplane.fill")
                                Text("Написать в Telegram")
                            }
                            .font(.caption)
                            .fontWeight(.semibold)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color.blue.opacity(0.15))
                            .foregroundColor(.blue)
                            .cornerRadius(8)
                        }
                        
                        Button("Скрыть") {
                            dismissAction()
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.yellow.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Предупреждение о грядущем обновлении функции Домашние задания")
    }
}

// MARK: - Homework Photos Sheet

struct HomeworkPhotosSheet: View {
    let homework: Homework
    @Environment(\.dismiss) private var dismiss
    @State private var selectedImageURL: URL?
    @State private var showingExportSheet = false
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(homework.imageAttachments, id: \.self) { attachment in
                        Button {
                            selectedImageURL = AttachmentManager.shared.getFileURL(attachment)
                        } label: {
                            if let image = AttachmentManager.shared.loadImage(attachment) {
                                Image(uiImage: image)
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(width: 120, height: 120)
                                    .clipped()
                                    .cornerRadius(12)
                            } else {
                                Rectangle()
                                    .fill(Color.gray.opacity(0.3))
                                    .frame(width: 120, height: 120)
                                    .cornerRadius(12)
                                    .overlay(
                                        Image(systemName: "photo")
                                            .font(.title2)
                                            .foregroundColor(.gray)
                                    )
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Фотографии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text(homework.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button {
                            showingExportSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                        }
                        
                        Button("Закрыть") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .sheet(item: Binding<IdentifiableURL?>(
            get: { selectedImageURL.map(IdentifiableURL.init) },
            set: { _ in selectedImageURL = nil }
        )) { identifiableURL in
            ImageViewerSheet(imageURL: identifiableURL.url)
        }
        .sheet(isPresented: $showingExportSheet) {
            PhotoExportSheet(imageAttachments: homework.imageAttachments)
        }
    }
}

// MARK: - Photo Export Sheet

struct PhotoExportSheet: View {
    let imageAttachments: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Экспорт фотографий")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Выберите, куда экспортировать \(imageAttachments.count) фотографий:")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 16) {
                    Button {
                        exportToPhotos()
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "photo.on.rectangle.angled")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.blue)
                                .cornerRadius(10)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Сохранить в галерею")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Добавить фото в приложение \"Фото\"")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button {
                        showingShareSheet = true
                    } label: {
                        HStack(spacing: 16) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title2)
                                .foregroundColor(.white)
                                .frame(width: 40, height: 40)
                                .background(Color.green)
                                .cornerRadius(10)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Поделиться")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Отправить в другие приложения")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                        }
                        .padding()
                        .background(Color(.systemBackground))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(.systemGray4), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Экспорт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: imageAttachments.compactMap { AttachmentManager.shared.loadImage($0) })
        }
    }
    
    private func exportToPhotos() {
        let images = imageAttachments.compactMap { AttachmentManager.shared.loadImage($0) }
        
        for image in images {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
        }
    }
    
}

// MARK: - ShareSheet UIViewControllerRepresentable

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Настройка для iPad
        if let popover = controller.popoverPresentationController {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
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
    @State private var selectedImages: [UIImage] = []
    @State private var showingPhotoSelection = false
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
                
                Section("Фотографии") {
                    Button {
                        showingPhotoSelection = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Добавить фото")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Прикрепить фотографии к заданию")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            if !selectedImages.isEmpty {
                                Text("\(selectedImages.count)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                    }
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
        .sheet(isPresented: $showingPhotoSelection) {
            PhotoSelectionSheet(showingSheet: $showingPhotoSelection, selectedImages: $selectedImages)
        }
        .onChange(of: selectedImages) { newImages in
            // Новые изображения будут сохранены при нажатии "Сохранить"
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
        
        // Сохраняем выбранные изображения
        for image in selectedImages {
            if let filename = AttachmentManager.shared.saveImage(image) {
                homework.addAttachment(filename)
            }
        }
        
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

struct EditHomeworkSheet: View {
    let homework: Homework
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingHomeworks: [Homework]
    
    @State private var title = ""
    @State private var subject = ""
    @State private var description = ""
    @State private var dueDate = Date()
    @State private var priority = HomeworkPriority.medium
    @State private var isCompleted = false
    @State private var suggestedSubjects: [String] = []
    @State private var showSuggestions = false
    @State private var selectedImages: [UIImage] = []
    @State private var showingPhotoSelection = false
    @AppStorage("subjectPresets") private var subjectPresetsStorage: String = ""
    
    init(homework: Homework) {
        self.homework = homework
    }
    
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
                
                Section("Статус") {
                    Toggle("Выполнено", isOn: $isCompleted)
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
                
                Section("Фотографии") {
                    Button {
                        showingPhotoSelection = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Добавить фото")
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text("Прикрепить фотографии к заданию")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            let totalPhotos = selectedImages.count + homework.imageAttachments.count
                            if totalPhotos > 0 {
                                Text("\(totalPhotos)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.blue)
                                    .cornerRadius(10)
                            }
                        }
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                    }
                    
                    // Отображение существующих фотографий
                    if !homework.imageAttachments.isEmpty {
                        AttachmentsView(attachments: homework.imageAttachments) { attachment in
                            homework.removeAttachment(attachment)
                        }
                    }
                }
            }
            .navigationTitle("Редактирование задания")
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
        .sheet(isPresented: $showingPhotoSelection) {
            PhotoSelectionSheet(showingSheet: $showingPhotoSelection, selectedImages: $selectedImages)
        }
        .onChange(of: selectedImages) { newImages in
            // Новые изображения будут сохранены при нажатии "Сохранить"
        }
        .onAppear {
            loadHomeworkData()
        }
    }
    
    private func loadHomeworkData() {
        title = homework.title
        subject = homework.subject
        description = homework.desc
        dueDate = homework.dueDate
        priority = homework.priority
        isCompleted = homework.isCompleted
    }
    
    private func saveHomework() {
        homework.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        homework.subject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        homework.desc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        homework.dueDate = dueDate
        homework.priority = priority
        homework.isCompleted = isCompleted
        
        // Сохраняем новые изображения
        for image in selectedImages {
            if let filename = AttachmentManager.shared.saveImage(image) {
                homework.addAttachment(filename)
            }
        }
        
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
        _selectedFaculty = State(initialValue: nil)
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
                            ForEach(scheduleService.faculties) { faculty in
                                Text(faculty.name).tag(faculty as Faculty?)
                            }
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        
                        if !scheduleService.facultiesMissingIDs.isEmpty {
                            FacultyMissingIdBanner(missingNames: scheduleService.facultiesMissingIDs)
                                .padding(.top, 8)
                        }
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
            await scheduleService.ensureFacultiesLoaded()
            
            // Проставляем текущий факультет пользователя из динамического списка (или как fallback — из статического)
            if selectedFaculty == nil {
                selectedFaculty =
                    scheduleService.faculties.first(where: { $0.id == user.facultyId }) ??
                    Faculty.allFaculties.first(where: { $0.id == user.facultyId })
            }
            
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

// MARK: - News Tab

struct NewsTab: View {
    let isInSplitView: Bool
    @StateObject private var newsAPIClient = DVGUPSNewsAPIClient()
    @State private var newsItems: [NewsItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var currentOffset = 0
    @State private var hasMorePages = true
    @State private var selectedNewsItem: NewsItem?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    var body: some View {
        SwiftUI.Group {
            if isInSplitView {
                // iPad layout
                newsContent
                    .navigationTitle("Новости ДВГУПС")
                    .navigationBarTitleDisplayMode(.large)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarTrailing) {
                            refreshButton
                        }
                    }
            } else {
                // iPhone layout
                NavigationView {
                    newsContent
                        .navigationTitle("Новости ДВГУПС")
                        .navigationBarTitleDisplayMode(.large)
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                refreshButton
                            }
                        }
                }
            }
        }
        .task {
            await loadInitialNews()
        }
        .refreshable {
            await refreshNews()
        }
        .sheet(item: $selectedNewsItem) { item in
            NewsDetailSheet(newsItem: item)
        }
    }
    
    @ViewBuilder
    private var newsContent: some View {
        VStack(spacing: 0) {
            if let errorMessage = errorMessage {
                ErrorBanner(message: errorMessage) {
                    self.errorMessage = nil
                }
                .padding(.horizontal)
                .padding(.top)
            }
            
            if newsItems.isEmpty && isLoading {
                LoadingNewsView()
            } else if newsItems.isEmpty {
                EmptyNewsView() {
                    Task { await loadInitialNews() }
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: isIPad ? 20 : 16) {
                        ForEach(newsItems) { item in
                            NewsCard(newsItem: item, isCompact: !isIPad) {
                                selectedNewsItem = item
                            }
                        }
                        
                        // Пагинация
                        if hasMorePages {
                            LoadMoreView(isLoading: isLoading) {
                                Task { await loadMoreNews() }
                            }
                        }
                    }
                    .padding(.horizontal, isIPad ? 24 : 16)
                    .padding(.vertical, isIPad ? 20 : 16)
                }
            }
        }
    }
    
    @ViewBuilder
    private var refreshButton: some View {
        Button {
            Task { await refreshNews() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .foregroundColor(.orange)
                .rotationEffect(.degrees(isLoading ? 360 : 0))
                .animation(isLoading ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isLoading)
        }
        .disabled(isLoading)
    }
    
    // MARK: - Data Loading
    
    private func loadInitialNews() async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        
        do {
            let response = try await newsAPIClient.fetchNews(offset: 0)
            await MainActor.run {
                self.newsItems = response.items
                self.currentOffset = response.nextOffset
                self.hasMorePages = response.hasMorePages
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
    
    private func refreshNews() async {
        currentOffset = 0
        await loadInitialNews()
    }
    
    private func loadMoreNews() async {
        guard !isLoading && hasMorePages else { return }
        
        isLoading = true
        
        do {
            let response = try await newsAPIClient.fetchNews(offset: currentOffset)
            await MainActor.run {
                self.newsItems.append(contentsOf: response.items)
                self.currentOffset = response.nextOffset
                self.hasMorePages = response.hasMorePages
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

// MARK: - News Components

struct NewsCard: View {
    let newsItem: NewsItem
    let isCompact: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            action()
        }) {
            VStack(alignment: .leading, spacing: 12) {
                // Изображение (если есть)
                if let imageURL = newsItem.imageURL, 
                   let url = URL(string: imageURL), 
                   !imageURL.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxHeight: isCompact ? 120 : 160)
                                .clipped()
                                .cornerRadius(12)
                        case .failure(_):
                            // Не показываем никакой плейсхолдер при ошибке загрузки
                            EmptyView()
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.2))
                                .overlay(
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                )
                                .frame(maxHeight: isCompact ? 120 : 160)
                                .cornerRadius(12)
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                
                // Заголовок
                Text(newsItem.title)
                    .font(isCompact ? .headline : .title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                
                // Описание
                if !newsItem.description.isEmpty {
                    Text(newsItem.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(isCompact ? 3 : 4)
                }
                
                // Футер с датой и просмотрами
                HStack {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.caption)
                            .foregroundColor(.orange)
                        
                        Text(newsItem.date, formatter: NewsItem.displayDateFormatter)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if newsItem.hits > 0 {
                        HStack(spacing: 4) {
                            Image(systemName: "eye")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text("\(newsItem.hits)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(isCompact ? 16 : 20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct LoadingNewsView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .progressViewStyle(CircularProgressViewStyle(tint: .orange))
            
            Text("Загрузка новостей...")
                .font(.headline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct EmptyNewsView: View {
    let retryAction: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "newspaper")
                .font(.system(size: 60))
                .foregroundColor(.orange.opacity(0.6))
            
            Text("Новости не найдены")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            
            Text("Попробуйте обновить страницу")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button("Обновить") {
                retryAction()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.orange)
            .foregroundColor(.white)
            .cornerRadius(12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

struct LoadMoreView: View {
    let isLoading: Bool
    let action: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            if isLoading {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .orange))
                    .scaleEffect(0.8)
                
                Text("Загрузка...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Button("Загрузить ещё") {
                    action()
                }
                .font(.subheadline)
                .fontWeight(.medium)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Color.orange)
                .foregroundColor(.white)
                .cornerRadius(20)
            }
        }
        .padding(.vertical, 20)
    }
}

struct NewsDetailSheet: View {
    let newsItem: NewsItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Изображение (если есть)
                    if let imageURL = newsItem.imageURL,
                       let url = URL(string: imageURL),
                       !imageURL.isEmpty {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxHeight: 250)
                                    .clipped()
                                    .cornerRadius(16)
                            case .failure(_):
                                // Не показываем изображение при ошибке загрузки
                                EmptyView()
                            case .empty:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.2))
                                    .overlay(
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle())
                                    )
                                    .frame(maxHeight: 250)
                                    .cornerRadius(16)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    
                    // Заголовок
                    Text(newsItem.title)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    // Мета информация
                    HStack {
                        Text(newsItem.date, formatter: NewsItem.displayDateFormatter)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if newsItem.hits > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "eye")
                                    .font(.caption)
                                Text("\(newsItem.hits)")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                    
                    Divider()
                    
                    // Основной текст
                    if !newsItem.fullText.isEmpty {
                        Text(newsItem.fullText)
                            .font(.body)
                            .foregroundColor(.primary)
                    } else {
                        Text(newsItem.description)
                            .font(.body)
                            .foregroundColor(.primary)
                    }
                    
                    Spacer(minLength: 40)
                }
                .padding(20)
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
        .presentationDragIndicator(.visible)
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
