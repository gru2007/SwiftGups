import SwiftUI

@MainActor
struct DVGUPSAuthStatusCard: View {
    @ObservedObject var authService: DVGUPSAuthService
    var showsActionHint: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(tintColor.opacity(0.14))
                            .frame(width: 44, height: 44)

                        Image(systemName: iconName)
                            .font(.headline)
                            .foregroundStyle(tintColor)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Личный кабинет ДВГУПС")
                            .font(.headline)
                            .foregroundStyle(.primary)

                        Text(authService.status.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)

                        Text(authService.status.message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 12)

                    Text(statusBadgeTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(tintColor)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(tintColor.opacity(0.12))
                        )
                }

                if showsActionHint {
                    HStack(spacing: 8) {
                        Text(actionTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(tintColor)

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(tintColor.opacity(0.16), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var iconName: String {
        switch authService.status {
        case .unknown, .checking:
            return "lock.rotation"
        case .authenticated:
            return "checkmark.shield.fill"
        case .credentialsMissing:
            return "lock.shield.fill"
        case .failed:
            return "exclamationmark.shield.fill"
        }
    }

    private var tintColor: Color {
        switch authService.status {
        case .unknown, .checking:
            return .blue
        case .authenticated:
            return .green
        case .credentialsMissing:
            return .orange
        case .failed:
            return .red
        }
    }

    private var statusBadgeTitle: String {
        switch authService.status {
        case .unknown, .credentialsMissing:
            return "Нужно действие"
        case .checking:
            return "Проверяем"
        case .authenticated:
            return "Активно"
        case .failed:
            return "Ошибка"
        }
    }

    private var actionTitle: String {
        switch authService.status {
        case .unknown, .credentialsMissing:
            return "Подключить личный кабинет"
        case .checking:
            return "Показать детали"
        case .authenticated:
            return "Управлять доступом"
        case .failed:
            return "Обновить вход"
        }
    }
}

private enum DVGUPSAuthField: Hashable {
    case login
    case password
}

@MainActor
struct DVGUPSAuthSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authService = DVGUPSAuthService.shared

    @State private var login: String = ""
    @State private var password: String = ""
    @State private var isWorking = false
    @State private var inlineError: String?
    @FocusState private var focusedField: DVGUPSAuthField?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    authHero

                    DVGUPSAuthStatusCard(
                        authService: authService,
                        showsActionHint: false,
                        action: {}
                    )
                    .disabled(true)

                    quickStartCard
                    credentialsCard

                    if let inlineError, !inlineError.isEmpty {
                        DVGUPSAuthInlineMessage(
                            title: inlineErrorTitle,
                            message: inlineError,
                            tintColor: .red,
                            icon: "exclamationmark.octagon.fill"
                        )
                    }

                    actionButtons
                }
                .padding(20)
            }
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle("ЛК ДВГУПС")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            let storedCredentials = authService.loadStoredCredentials()
            login = storedCredentials?.login ?? authService.storedLogin ?? ""
            password = storedCredentials?.password ?? ""
            await authService.refreshStatusIfNeeded()

            if login.isEmpty {
                focusedField = .login
            } else if password.isEmpty {
                focusedField = .password
            }
        }
    }

    private var authHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color.blue, Color.cyan],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 60, height: 60)

                    Image(systemName: "person.badge.key.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(heroTitle)
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.primary)

                    Text(heroMessage)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let storedLogin = authService.storedLogin, !storedLogin.isEmpty {
                Label("Сохранённый логин: \(storedLogin)", systemImage: "checkmark.circle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var quickStartCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Как это работает")
                .font(.headline)

            DVGUPSAuthStepRow(
                icon: "1.circle.fill",
                title: "Введите логин и пароль от ЛК",
                message: "Данные сохраняются только на этом устройстве в системном Keychain."
            )

            DVGUPSAuthStepRow(
                icon: "2.circle.fill",
                title: "Приложение обновит cookie-сессию",
                message: "SwiftGups автоматически связывает lk.dvgups.ru и dvgups.ru."
            )

            DVGUPSAuthStepRow(
                icon: "3.circle.fill",
                title: "Расписание и Live Activity заработают в фоне",
                message: "При следующем 401 приложение сначала попробует тихо переавторизоваться."
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Учётные данные")
                .font(.headline)

            VStack(alignment: .leading, spacing: 10) {
                Text("Логин")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                TextField("Например, ИвановИИ", text: $login)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.username)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .login)
                    .onSubmit {
                        focusedField = .password
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Пароль")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)

                SecureField("Введите пароль", text: $password)
                    .textContentType(.password)
                    .privacySensitive()
                    .submitLabel(.go)
                    .focused($focusedField, equals: .password)
                    .onSubmit {
                        saveAndAuthorize()
                    }
                    .padding(.horizontal, 14)
                    .frame(height: 50)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.tertiarySystemGroupedBackground))
                    )
            }

            DVGUPSAuthInlineMessage(
                title: "Безопасность",
                message: "Логин и пароль не отправляются никуда, кроме официального ЛК ДВГУПС, и хранятся только в Keychain этого iPhone.",
                tintColor: .blue,
                icon: "lock.circle.fill"
            )
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: saveAndAuthorize) {
                HStack(spacing: 10) {
                    if isWorking {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }

                    Text(primaryActionTitle)
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isWorking || !canSubmitCredentials)

            if authService.storedLogin != nil {
                Button(action: checkAuthorization) {
                    Text("Проверить текущий доступ")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
                
                Button(role: .destructive, action: clearAuthorization) {
                    Text("Удалить сохранённый доступ")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.bordered)
                .disabled(isWorking)
            }
        }
    }

    private var heroTitle: String {
        switch authService.status {
        case .authenticated:
            return "Личный кабинет уже подключён"
        case .failed:
            return "Нужно обновить вход"
        case .checking:
            return "Проверяем доступ к расписанию"
        case .unknown, .credentialsMissing:
            return "Подключите ЛК для расписания"
        }
    }

    private var heroMessage: String {
        switch authService.status {
        case .authenticated:
            return "Вы сможете загружать расписание без ручного входа, а фоновые обновления и Live Activity будут работать стабильнее."
        case .failed:
            return "Сессия устарела или пароль изменился. Обновите логин и пароль, чтобы снова открыть доступ к расписанию."
        case .checking:
            return "SwiftGups проверяет действительность сессии и при необходимости автоматически переавторизуется."
        case .unknown, .credentialsMissing:
            return "Теперь расписание ДВГУПС требует вход через личный кабинет. Это можно сделать один раз, а дальше приложение будет поддерживать сессию само."
        }
    }

    private var primaryActionTitle: String {
        authService.storedLogin == nil ? "Подключить личный кабинет" : "Сохранить и войти заново"
    }

    private var inlineErrorTitle: String {
        if authService.storedLogin == nil {
            return "Не удалось подключить ЛК"
        }
        return "Не удалось обновить доступ"
    }

    private var canSubmitCredentials: Bool {
        !trimmedLogin.isEmpty && !normalizedPassword.isEmpty
    }

    private var trimmedLogin: String {
        login.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedPassword: String {
        password.trimmingCharacters(in: .newlines)
    }

    private func saveAndAuthorize() {
        inlineError = nil

        guard canSubmitCredentials else {
            inlineError = "Введите логин и пароль от личного кабинета."
            return
        }

        isWorking = true

        Task {
            do {
                try await authService.saveCredentials(login: login, password: password)
                await MainActor.run {
                    isWorking = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    inlineError = error.localizedDescription
                    isWorking = false
                }
            }
        }
    }

    private func checkAuthorization() {
        inlineError = nil
        isWorking = true

        Task {
            let resolved = await authService.refreshStatus(forceReauthentication: false)
            await MainActor.run {
                if case .failed(let message) = resolved {
                    inlineError = message
                }
                isWorking = false
            }
        }
    }

    private func clearAuthorization() {
        inlineError = nil
        isWorking = true

        Task {
            do {
                try await authService.clearCredentials()
                await MainActor.run {
                    login = ""
                    password = ""
                    focusedField = .login
                    isWorking = false
                }
            } catch {
                await MainActor.run {
                    inlineError = error.localizedDescription
                    isWorking = false
                }
            }
        }
    }
}

struct DVGUPSFirstLaunchHintCard: View {
    let isConnected: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isConnected ? "checkmark.shield.fill" : "lock.shield.fill")
                    .font(.title3)
                    .foregroundStyle(isConnected ? .green : .blue)

                VStack(alignment: .leading, spacing: 4) {
                    Text(isConnected ? "ЛК ДВГУПС уже подключён" : "Для расписания нужен вход в ЛК ДВГУПС")
                        .font(.headline)

                    Text(
                        isConnected
                        ? "После завершения настройки расписание будет загружаться через сохранённую сессию."
                        : "Новая система расписания использует личный кабинет. Можно подключить его сейчас или позже во вкладке «Профиль»."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button(isConnected ? "Проверить доступ" : "Подключить ЛК сейчас", action: action)
                .buttonStyle(.borderedProminent)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemGray6))
        )
    }
}

private struct DVGUPSAuthStepRow: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.headline)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct DVGUPSAuthInlineMessage: View {
    let title: String
    let message: String
    let tintColor: Color
    let icon: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tintColor)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tintColor.opacity(0.08))
        )
    }
}
