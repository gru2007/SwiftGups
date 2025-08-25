//
//  MainAppView.swift
//  SwiftGups
//
//  Created by Assistant on 25.08.2025.
//

import SwiftUI
import SwiftData

struct MainAppView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var users: [User]
    @StateObject private var cloudKitService = CloudKitService()
    
    var body: some View {
        SwiftUI.Group {
            if let currentUser = users.first {
                TabBarView(currentUser: currentUser)
                    .environmentObject(cloudKitService)
            } else {
                // Регистрация всегда в полноэкранном режиме (не внутри NavigationSplitView)
                RegistrationView()
                    .environmentObject(cloudKitService)
                    .ignoresSafeArea(.all, edges: .top) // Полноэкранный режим на iPad
            }
        }
        .animation(.easeInOut(duration: 0.3), value: users.count)
        .cloudKitAlert(cloudKitService)
    }
}

// MARK: - Registration View

struct RegistrationView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var cloudKitService: CloudKitService
    @StateObject private var scheduleService = ScheduleService()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var name: String = ""
    @State private var selectedFaculty: Faculty?
    @State private var selectedGroup: Group?
    @State private var searchText: String = ""
    @State private var showingProgress = false
    @State private var progressStep = 0
    @State private var errorMessage: String?
    
    private var isIPad: Bool {
        horizontalSizeClass == .regular
    }
    
    var body: some View {
        // НЕ используем NavigationView - это создает sidebar на iPad
        ZStack {
            // Фон
            LinearGradient(
                colors: [Color.blue.opacity(0.1), Color.purple.opacity(0.1)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            if isIPad {
                // iPad версия с двухколоночной компоновкой
                HStack(spacing: 40) {
                    // Левая колонка - приветствие
                    VStack(spacing: 24) {
                        Spacer()
                        
                        ZStack {
                            Circle()
                                .fill(LinearGradient(
                                    colors: [.blue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .frame(width: 150, height: 150)
                                .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)
                            
                            Text("🎓")
                                .font(.system(size: 60))
                        }
                        .scaleEffect(showingProgress ? 1.1 : 1.0)
                        .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: showingProgress)
                        
                        VStack(spacing: 16) {
                            Text("Добро пожаловать!")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                                .foregroundStyle(
                                    LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                            
                            Text("Настройте свой профиль для удобного просмотра расписания и управления домашними заданиями")
                                .font(.title3)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                        }
                        
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Правая колонка - форма регистрации
                    VStack(spacing: 24) {
                        // Статус CloudKit
                        CloudKitStatusView(cloudKitService: cloudKitService)
                        
                        // Форма
                        registrationForm
                        
                        // Кнопка завершения
                        completionButton
                    }
                    .frame(maxWidth: 400)
                }
                .padding(40)
            } else {
                // iPhone версия - тоже без NavigationView
                ScrollView {
                    VStack(spacing: 32) {
                        // Заголовок с анимацией
                        VStack(spacing: 16) {
                            ZStack {
                                Circle()
                                    .fill(LinearGradient(
                                        colors: [.blue, .purple],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ))
                                    .frame(width: 120, height: 120)
                                    .shadow(color: .blue.opacity(0.3), radius: 20, x: 0, y: 10)
                                
                                Text("🎓")
                                    .font(.system(size: 50))
                            }
                            .scaleEffect(showingProgress ? 1.1 : 1.0)
                            .animation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true), value: showingProgress)
                            
                            VStack(spacing: 8) {
                                Text("Добро пожаловать!")
                                    .font(.title)
                                    .fontWeight(.bold)
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [.blue, .purple],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                
                                Text("Настройте свой профиль для удобного просмотра расписания")
                                    .font(.body)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                        .padding(.top, 40)
                        
                        // Статус CloudKit
                        CloudKitStatusView(cloudKitService: cloudKitService)
                            .padding(.horizontal, 20)
                        
                        // Форма регистрации
                        registrationForm
                            .padding(.horizontal, 20)
                        
                        // Кнопка завершения  
                        completionButton
                            .padding(.horizontal, 20)
                            .padding(.bottom, 40)
                    }
                }
            }
        }
        .task {
            if selectedFaculty != nil {
                await scheduleService.loadGroups()
            }
        }
    }
    
    private var isFormValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        selectedFaculty != nil &&
        selectedGroup != nil
    }
    
    @ViewBuilder
    private var registrationForm: some View {
        VStack(spacing: 24) {
            // Имя
            CustomTextField(
                title: "Ваше имя",
                text: $name,
                icon: "person.fill",
                placeholder: "Введите ваше имя"
            )
            
            // Выбор факультета
            FacultyPickerView(
                selectedFaculty: $selectedFaculty,
                scheduleService: scheduleService
            )
            
            // Выбор группы
            if selectedFaculty != nil {
                GroupPickerView(
                    selectedGroup: $selectedGroup,
                    searchText: $searchText,
                    scheduleService: scheduleService
                )
            }
            
            // Сообщение об ошибке
            if let errorMessage = errorMessage {
                ErrorBanner(message: errorMessage) {
                    self.errorMessage = nil
                }
            }
        }
    }
    
    @ViewBuilder
    private var completionButton: some View {
        Button(action: completeRegistration) {
            HStack {
                if showingProgress {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                        .scaleEffect(0.8)
                }
                
                Text(showingProgress ? "Сохранение..." : "Начать использование")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                LinearGradient(
                    colors: isFormValid ? [.blue, .purple] : [.gray, .gray.opacity(0.7)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .foregroundColor(.white)
            .cornerRadius(16)
            .shadow(color: isFormValid ? .blue.opacity(0.3) : .clear, radius: 10, x: 0, y: 5)
            .scaleEffect(showingProgress ? 0.95 : 1.0)
        }
        .disabled(!isFormValid || showingProgress)
    }
    
    private func completeRegistration() {
        guard let faculty = selectedFaculty,
              let group = selectedGroup else { return }
        
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Пожалуйста, введите ваше имя"
            return
        }
        
        showingProgress = true
        
        // Создаем пользователя
        let newUser = User(
            name: trimmedName,
            facultyId: faculty.id,
            facultyName: faculty.name,
            groupId: group.id,
            groupName: group.name
        )
        
        modelContext.insert(newUser)
        
        do {
            try modelContext.save()
            
            // Небольшая задержка для показа анимации
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                showingProgress = false
            }
        } catch {
            showingProgress = false
            errorMessage = "Ошибка сохранения данных: \(error.localizedDescription)"
        }
    }
}

// MARK: - Custom Components

struct CustomTextField: View {
    let title: String
    @Binding var text: String
    let icon: String
    let placeholder: String
    
    @FocusState private var isFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            TextField(placeholder, text: $text)
                .focused($isFocused)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .stroke(isFocused ? Color.blue : Color.clear, lineWidth: 2)
                )
        }
    }
}

struct FacultyPickerView: View {
    @Binding var selectedFaculty: Faculty?
    @ObservedObject var scheduleService: ScheduleService
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundColor(.blue)
                Text("Институт/Факультет")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            Menu {
                ForEach(Faculty.allFaculties) { faculty in
                    Button(action: {
                        selectedFaculty = faculty
                        scheduleService.selectFaculty(faculty)
                    }) {
                        HStack {
                            Text(faculty.name)
                            if selectedFaculty?.id == faculty.id {
                                Spacer()
                                Image(systemName: "checkmark")
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                }
            } label: {
                HStack {
                    Text(selectedFaculty?.name ?? "Выберите институт/факультет")
                        .foregroundColor(selectedFaculty != nil ? .primary : .secondary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    
                    Spacer()
                    
                    Image(systemName: "chevron.down")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .frame(height: 44)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
            }
        }
    }
}

struct GroupPickerView: View {
    @Binding var selectedGroup: Group?
    @Binding var searchText: String
    @ObservedObject var scheduleService: ScheduleService
    
    private var filteredGroups: [Group] {
        scheduleService.filteredGroups(searchText: searchText)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "person.3.fill")
                    .foregroundColor(.blue)
                Text("Группа")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            // Поле поиска
            SearchBar(text: $searchText, placeholder: "Поиск группы...")
            
            if scheduleService.isLoading {
                HStack {
                    Spacer()
                    ProgressView("Загрузка групп...")
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding()
            } else if filteredGroups.isEmpty && scheduleService.selectedFaculty != nil {
                Text("Группы не найдены")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                // Список групп
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(filteredGroups.prefix(6)) { group in
                        GroupSelectionCard(
                            group: group,
                            isSelected: selectedGroup?.id == group.id
                        ) {
                            selectedGroup = group
                            searchText = ""
                        }
                    }
                }
                
                if filteredGroups.count > 6 {
                    Text("И еще \(filteredGroups.count - 6) групп...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 8)
                }
            }
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(PlainTextFieldStyle())
            
            if !text.isEmpty {
                Button("Очистить") {
                    text = ""
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
        .frame(height: 44)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

struct GroupSelectionCard: View {
    let group: Group
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: {
            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
            impactFeedback.impactOccurred()
            
            withAnimation(.easeInOut(duration: 0.2)) {
                action()
            }
        }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(group.name)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)
                
                Text(group.fullName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.8) : .secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                
                Spacer()
            }
            .frame(height: 80)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        isSelected
                        ? LinearGradient(colors: [.blue, .purple], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [Color(.systemGray6)], startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .shadow(color: isSelected ? .blue.opacity(0.3) : .clear, radius: 5, x: 0, y: 2)
            )
        }
        .scaleEffect(isSelected ? 1.02 : 1.0)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }
}

struct ErrorBanner: View {
    let message: String
    let dismissAction: () -> Void
    
    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
                .lineLimit(3)
            
            Spacer()
            
            Button("Закрыть") {
                dismissAction()
            }
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

#Preview {
    MainAppView()
        .modelContainer(for: [User.self, Homework.self], inMemory: true)
}
