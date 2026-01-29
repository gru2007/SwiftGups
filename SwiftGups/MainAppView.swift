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
    @State private var facultySearchText: String = ""
    @State private var showingProgress = false
    @State private var progressStep = 0
    @State private var errorMessage: String?
    @State private var skipFacultySelection = false // Пропуск выбора института/факультета
    @State private var skipGroupSelection = false // Пропуск выбора группы при недоступности сайта
    @FocusState private var isNameFieldFocused: Bool
    
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
        .onDisappear {
            // Закрываем клавиатуру при выходе с экрана
            isNameFieldFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .task {
            await scheduleService.ensureFacultiesLoaded()
            if selectedFaculty != nil {
                await scheduleService.loadGroups()
            }
        }
    }
    
    private var isFormValid: Bool {
        // Форма валидна, если введено имя,
        // выбран факультет (или шаг пропущен),
        // и выбрана группа (или шаг пропущен / факультет пропущен).
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasFaculty = selectedFaculty != nil || skipFacultySelection
        let hasGroup = selectedGroup != nil || skipGroupSelection || skipFacultySelection
        return hasName && hasFaculty && hasGroup
    }
    
    @ViewBuilder
    private var registrationForm: some View {
        VStack(spacing: 24) {
            // Имя
            CustomTextField(
                title: "Ваше имя",
                text: $name,
                icon: "person.fill",
                placeholder: "Введите ваше имя",
                isFocused: $isNameFieldFocused
            )
            
            // Выбор факультета
            if !skipFacultySelection {
                FacultyPickerView(
                    selectedFaculty: $selectedFaculty,
                    searchText: $facultySearchText,
                    scheduleService: scheduleService
                )

                Button("Продолжить без выбора института") {
                    skipFacultySelection = true
                    selectedFaculty = nil
                    selectedGroup = nil
                    skipGroupSelection = true
                    facultySearchText = ""
                    searchText = ""
                    errorMessage = nil
                }
                .font(.caption)
                .foregroundColor(.blue)
            } else {
                // Сообщение о пропуске выбора института
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "building.2.fill")
                            .foregroundColor(.blue)
                        Text("Институт/Факультет")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    Text("Выбор института пропущен. Вы сможете выбрать его позже в профиле.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Выбрать институт") {
                        skipFacultySelection = false
                        skipGroupSelection = false
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            
            // Выбор группы
            if selectedFaculty != nil && !skipGroupSelection && !skipFacultySelection {
                GroupPickerView(
                    selectedGroup: $selectedGroup,
                    searchText: $searchText,
                    scheduleService: scheduleService
                )

                // Кнопка пропуска выбора группы
                Button("Сайт недоступен? Продолжить без группы") {
                    skipGroupSelection = true
                    selectedGroup = nil
                    errorMessage = nil
                }
                .font(.caption)
                .foregroundColor(.blue)
            } else if skipGroupSelection {
                // Сообщение о пропуске выбора группы
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "person.3.fill")
                            .foregroundColor(.blue)
                        Text("Группа")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }

                    Text("Выбор группы пропущен. Вы сможете выбрать её позже в профиле.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Выбрать группу") {
                        skipGroupSelection = false
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }

            // Сообщение об ошибке
            if let errorMessage = errorMessage, !skipGroupSelection && !skipFacultySelection {
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
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Пожалуйста, введите ваше имя"
            return
        }

        // Закрываем клавиатуру перед сохранением
        isNameFieldFocused = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        
        showingProgress = true

        let facultyId = selectedFaculty?.id ?? ""
        let facultyName = selectedFaculty?.name ?? ""

        // Создаем пользователя, даже если институт/группа не выбраны
        let newUser = User(
            name: trimmedName,
            facultyId: facultyId,
            facultyName: facultyName,
            groupId: selectedGroup?.id ?? "",
            groupName: selectedGroup?.name ?? ""
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
    @FocusState.Binding var isFocused: Bool
    
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
    @Binding var searchText: String
    @ObservedObject var scheduleService: ScheduleService
    @State private var showVPNHint = false
    @State private var vpnHintTask: Task<Void, Never>?
    
    private var filteredFaculties: [Faculty] {
        scheduleService.filteredFaculties(searchText: searchText)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "building.2.fill")
                    .foregroundColor(.blue)
                Text("Институт/Факультет")
                    .font(.headline)
                    .foregroundColor(.primary)
            }
            
            // Поле поиска
            SearchBar(text: $searchText, placeholder: "Поиск института...")
            
            if scheduleService.isLoadingFaculties {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        ProgressView("Загрузка институтов...")
                            .foregroundColor(.secondary)
                        if showVPNHint {
                            VPNHintBanner()
                                .frame(maxWidth: 360)
                        }
                    }
                    Spacer()
                }
                .padding()
            } else if filteredFaculties.isEmpty && !scheduleService.faculties.isEmpty {
                Text("Институты не найдены")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else if scheduleService.faculties.isEmpty {
                Text("Нет доступных институтов")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                // Список институтов — показываем все
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(filteredFaculties) { faculty in
                        FacultySelectionCard(
                            faculty: faculty,
                            isSelected: selectedFaculty?.id == faculty.id
                        ) {
                            selectedFaculty = faculty
                            scheduleService.selectFaculty(faculty)
                        }
                    }
                }
            }
            
            FacultyMissingIdBanner(missingNames: scheduleService.facultiesMissingIDs)
        }
        .onAppear {
            updateVPNHint(isLoading: scheduleService.isLoadingFaculties)
        }
        .onChange(of: scheduleService.isLoadingFaculties) { newValue in
            updateVPNHint(isLoading: newValue)
        }
    }

    private func updateVPNHint(isLoading: Bool) {
        vpnHintTask?.cancel()
        vpnHintTask = nil

        if !isLoading {
            withAnimation(.easeInOut(duration: 0.2)) {
                showVPNHint = false
            }
            return
        }

        vpnHintTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            guard scheduleService.isLoadingFaculties else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVPNHint = true
                }
            }
        }
    }
}

struct GroupPickerView: View {
    @Binding var selectedGroup: Group?
    @Binding var searchText: String
    @ObservedObject var scheduleService: ScheduleService
    @State private var showVPNHint = false
    @State private var vpnHintTask: Task<Void, Never>?
    
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
            
            if scheduleService.isLoadingGroups {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        ProgressView("Загрузка групп...")
                            .foregroundColor(.secondary)
                        if showVPNHint {
                            VPNHintBanner()
                                .frame(maxWidth: 360)
                        }
                    }
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
                    ForEach(filteredGroups) { group in
                        GroupSelectionCard(
                            group: group,
                            isSelected: selectedGroup?.id == group.id
                        ) {
                            selectedGroup = group
                        }
                    }
                }
            }
        }
        .onAppear {
            updateVPNHint(isLoading: scheduleService.isLoadingGroups)
        }
        .onChange(of: scheduleService.isLoadingGroups) { newValue in
            updateVPNHint(isLoading: newValue)
        }
    }

    private func updateVPNHint(isLoading: Bool) {
        vpnHintTask?.cancel()
        vpnHintTask = nil

        if !isLoading {
            withAnimation(.easeInOut(duration: 0.2)) {
                showVPNHint = false
            }
            return
        }

        vpnHintTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            guard scheduleService.isLoadingGroups else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVPNHint = true
                }
            }
        }
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
