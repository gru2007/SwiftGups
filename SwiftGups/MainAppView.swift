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
    @ObservedObject private var authService = DVGUPSAuthService.shared
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    
    @State private var name: String = ""
    @State private var selectedFaculty: Faculty?
    @State private var selectedGroup: Group?
    @State private var showingProgress = false
    @State private var progressStep = 0
    @State private var errorMessage: String?
    @State private var skipGroupSelection = false // Пропуск выбора группы при недоступности сайта
    @State private var showingDVGUPSAuth = false
    @State private var lastKnownDVGUPSAuthStatus: DVGUPSAuthStatus = .unknown
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
        .sheet(isPresented: $showingDVGUPSAuth, onDismiss: handleDVGUPSAuthDismiss) {
            DVGUPSAuthSheet()
        }
        .onDisappear {
            // Закрываем клавиатуру при выходе с экрана
            isNameFieldFocused = false
            UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        }
        .task {
            await scheduleService.ensureGroupDirectoryLoaded()
            await authService.refreshStatusIfNeeded()
            lastKnownDVGUPSAuthStatus = authService.status
        }
    }
    
    private var isFormValid: Bool {
        // Институт больше не выбирается отдельно — он выводится из группы.
        let hasName = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasGroup = selectedGroup != nil || skipGroupSelection
        return hasName && hasGroup
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
            
            // Выбор группы: институт выбирать не нужно, справочник общий.
            if skipGroupSelection {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Группа", systemImage: "person.3.fill")
                        .font(.headline)
                        .foregroundStyle(.primary)

                    Text("Выбор группы пропущен. Вы сможете указать её позже в профиле.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Button("Выбрать группу") {
                        skipGroupSelection = false
                    }
                    .font(.subheadline)
                    .frame(minHeight: 44)
                }
            } else {
                GroupPicker(
                    scheduleService: scheduleService,
                    selectedGroupId: selectedGroup?.id
                ) { group in
                    selectedGroup = group
                    selectedFaculty = scheduleService.faculties.first { $0.id == group.facultyId }
                }

                Button("Сайт недоступен? Продолжить без группы") {
                    skipGroupSelection = true
                    selectedGroup = nil
                    errorMessage = nil
                }
                .font(.subheadline)
                .frame(minHeight: 44)
            }

            DVGUPSFirstLaunchHintCard(
                isConnected: authService.status.isAuthenticated || authService.storedLogin != nil
            ) {
                showingDVGUPSAuth = true
            }

            // Сообщение об ошибке
            if let errorMessage = errorMessage, !skipGroupSelection {
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

        // Группа могла прийти из поиска по всему вузу — тогда её институт
        // не совпадает с выбранным в списке, и сохранять надо институт группы.
        let groupFaculty = selectedGroup.flatMap { group in
            scheduleService.faculties.first { $0.id == group.facultyId }
        }
        let facultyId = groupFaculty?.id ?? selectedFaculty?.id ?? ""
        let facultyName = groupFaculty?.name ?? selectedFaculty?.name ?? ""

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

    private func handleDVGUPSAuthDismiss() {
        Task {
            let previousStatus = lastKnownDVGUPSAuthStatus
            let refreshedStatus = await authService.refreshStatus(forceReauthentication: false)
            lastKnownDVGUPSAuthStatus = refreshedStatus

            guard refreshedStatus.isAuthenticated, !previousStatus.isAuthenticated else {
                return
            }

            await refreshRegistrationScheduleData()
        }
    }

    /// После входа в ЛК справочник может стать полнее — перезагружаем его
    /// и восстанавливаем выбранную группу по ID.
    private func refreshRegistrationScheduleData() async {
        let previouslySelectedGroupId = selectedGroup?.id

        await scheduleService.loadGroupDirectory()

        guard let previouslySelectedGroupId else { return }

        selectedGroup = scheduleService.allGroups.first { $0.id == previouslySelectedGroupId }
        selectedFaculty = selectedGroup.flatMap { group in
            scheduleService.faculties.first { $0.id == group.facultyId }
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
