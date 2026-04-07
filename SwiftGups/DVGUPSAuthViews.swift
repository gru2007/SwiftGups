import SwiftUI

@MainActor
struct DVGUPSAuthStatusCard: View {
    @ObservedObject var authService: DVGUPSAuthService
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: iconName)
                        .font(.title3)
                        .foregroundColor(tintColor)
                        .frame(width: 28)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Личный кабинет ДВГУПС")
                            .font(.body)
                            .foregroundColor(.primary)

                        Text(authService.status.title)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }

                Text(authService.status.message)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
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
            return "lock.shield"
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
}

@MainActor
struct DVGUPSAuthSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var authService = DVGUPSAuthService.shared

    @State private var login: String = ""
    @State private var password: String = ""
    @State private var isWorking = false
    @State private var inlineError: String?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    DVGUPSAuthStatusCard(authService: authService) { }
                        .disabled(true)

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Учётные данные")
                            .font(.headline)

                        TextField("Логин ЛК", text: $login)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .textFieldStyle(.roundedBorder)

                        SecureField("Пароль", text: $password)
                            .textFieldStyle(.roundedBorder)

                        Text("Логин и пароль сохраняются только в системном Keychain этого устройства и используются для обновления cookie-сессии расписания.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let inlineError, !inlineError.isEmpty {
                        Text(inlineError)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }

                    VStack(spacing: 12) {
                        Button(action: saveAndAuthorize) {
                            HStack {
                                if isWorking {
                                    ProgressView()
                                        .progressViewStyle(.circular)
                                }
                                Text(authService.storedLogin == nil ? "Подключить личный кабинет" : "Обновить и войти заново")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 50)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isWorking)

                        Button(action: checkAuthorization) {
                            Text("Проверить авторизацию")
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                        }
                        .buttonStyle(.bordered)
                        .disabled(isWorking)

                        if authService.storedLogin != nil {
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
                .padding()
            }
            .navigationTitle("Авторизация ДВГУПС")
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
        }
    }

    private func saveAndAuthorize() {
        inlineError = nil
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
