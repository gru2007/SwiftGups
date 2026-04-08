import Foundation
import Security
import Combine

enum DVGUPSAuthStatus: Equatable {
    case unknown
    case checking
    case authenticated(login: String?)
    case credentialsMissing
    case failed(message: String)

    var isAuthenticated: Bool {
        if case .authenticated = self {
            return true
        }
        return false
    }

    var title: String {
        switch self {
        case .unknown:
            return "Подключите ЛК ДВГУПС"
        case .checking:
            return "Проверяем доступ"
        case .authenticated(let login):
            if let login, !login.isEmpty {
                return "Выполнен вход: \(login)"
            }
            return "Личный кабинет подключен"
        case .credentialsMissing:
            return "Нужен вход в ЛК ДВГУПС"
        case .failed:
            return "Нужно войти заново"
        }
    }

    var message: String {
        switch self {
        case .unknown:
            return "Подключите личный кабинет, чтобы расписание и Live Activity обновлялись без ручных действий."
        case .checking:
            return "Обновляем сессию между lk.dvgups.ru и dvgups.ru."
        case .authenticated:
            return "Расписание, повторный вход и фоновые обновления работают автоматически."
        case .credentialsMissing:
            return "Сохраните логин и пароль от личного кабинета. Они нужны для загрузки расписания и фоновых обновлений."
        case .failed(let message):
            return message
        }
    }
}

struct DVGUPSCredentials: Codable, Equatable {
    let login: String
    let password: String
}

enum DVGUPSKeychainError: LocalizedError {
    case unexpectedData
    case unhandled(status: OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedData:
            return "Не удалось прочитать сохранённые данные авторизации"
        case .unhandled(let status):
            return "Ошибка Keychain: \(status)"
        }
    }
}

struct DVGUPSCredentialsStore {
    private let service = "SwiftGups.DVGUPS.Auth"
    private let account = "main"

    func load() throws -> DVGUPSCredentials? {
        var query = baseQuery
        query[kSecReturnData as String] = kCFBooleanTrue
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data else {
                throw DVGUPSKeychainError.unexpectedData
            }
            return try JSONDecoder().decode(DVGUPSCredentials.self, from: data)
        case errSecItemNotFound:
            return nil
        default:
            throw DVGUPSKeychainError.unhandled(status: status)
        }
    }

    func save(_ credentials: DVGUPSCredentials) throws {
        let data = try JSONEncoder().encode(credentials)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        switch addStatus {
        case errSecSuccess:
            return
        case errSecDuplicateItem:
            let updates = [kSecValueData as String: data]
            let updateStatus = SecItemUpdate(baseQuery as CFDictionary, updates as CFDictionary)
            guard updateStatus == errSecSuccess else {
                throw DVGUPSKeychainError.unhandled(status: updateStatus)
            }
        default:
            throw DVGUPSKeychainError.unhandled(status: addStatus)
        }
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw DVGUPSKeychainError.unhandled(status: status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}

enum DVGUPSBrowserProfile {
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.1 Mobile/15E148 Safari/604.1"
    static let acceptLanguage = "ru"
    static let navigationAccept = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
    static let apiAccept = "application/json"

    static func applyNavigationHeaders(to request: inout URLRequest, referer: String? = nil) {
        request.setValue(navigationAccept, forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue("document", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("navigate", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue(referer == nil ? "none" : "same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("u=0, i", forHTTPHeaderField: "Priority")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
    }

    static func applyAPIHeaders(
        to request: inout URLRequest,
        accept: String,
        contentType: String? = nil,
        referer: String,
        origin: String? = nil
    ) {
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("u=3, i", forHTTPHeaderField: "Priority")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        if let contentType {
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        if let origin {
            request.setValue(origin, forHTTPHeaderField: "Origin")
        }
    }
}

private struct DVGUPSAuthResponse: Decodable {
    let success: Bool
    let data: Payload?

    struct Payload: Decodable {
        let user: User?
        let roles: [String]?

        struct User: Decodable {
            let login: String?
        }
    }
}

actor DVGUPSAuthCoordinator {
    private let session: URLSession
    private let credentialsStore: DVGUPSCredentialsStore
    private let cookieStorage: HTTPCookieStorage

    private var didBootstrapLK = false
    private var didBootstrapScheduleSite = false

    init(
        session: URLSession,
        credentialsStore: DVGUPSCredentialsStore = DVGUPSCredentialsStore(),
        cookieStorage: HTTPCookieStorage = .shared
    ) {
        self.session = session
        self.credentialsStore = credentialsStore
        self.cookieStorage = cookieStorage
    }

    func resolveStatus(forceReauthentication: Bool) async -> DVGUPSAuthStatus {
        do {
            if !forceReauthentication, let login = try await identifyMainSiteLogin() {
                return .authenticated(login: login)
            }

            guard let credentials = try credentialsStore.load() else {
                return .credentialsMissing
            }

            try await reauthorize(with: credentials)
            return .authenticated(login: credentials.login)
        } catch let error as APIError {
            switch error {
            case .authenticationRequired:
                return .credentialsMissing
            default:
                return .failed(message: error.localizedDescription)
            }
        } catch {
            return .failed(message: error.localizedDescription)
        }
    }

    func reauthorizeIfPossible() async throws {
        guard let credentials = try credentialsStore.load() else {
            print("🔐 DVGUPS auth: no saved credentials for silent reauth")
            throw APIError.authenticationRequired
        }

        print("🔐 DVGUPS auth: silent reauth started for \(credentials.login)")
        try await reauthorize(with: credentials)
    }

    func authorize(credentials: DVGUPSCredentials) async throws {
        clearSessionCookies()
        try await reauthorize(with: credentials)
    }

    func clearSessionCookies() {
        for cookie in cookieStorage.cookies ?? [] {
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            if domain == "dvgups.ru" || domain.hasSuffix(".dvgups.ru") {
                cookieStorage.deleteCookie(cookie)
            }
        }
        didBootstrapLK = false
        didBootstrapScheduleSite = false
    }

    private func reauthorize(with credentials: DVGUPSCredentials) async throws {
        try await bootstrapLKIfNeeded()
        try await authenticate(with: credentials)
        print("🔐 DVGUPS auth: authenticate succeeded for \(credentials.login)")

        guard try await identifyLKLogin() != nil else {
            throw APIError.invalidCredentials
        }

        // В браузере `dvgups.ru/` и `/public/schedule` открываются после успешного входа в LK.
        try await bootstrapScheduleSite(force: true)

        guard try await identifyMainSiteLogin() != nil else {
            throw APIError.invalidCredentials
        }

        print("🔐 DVGUPS auth: do-lk identify succeeded")
        try? await warmTimetableSession()
    }

    private func bootstrapLKIfNeeded() async throws {
        if !didBootstrapLK {
            try await bootstrapLKSession()
            didBootstrapLK = true
        }
    }

    private func bootstrapScheduleSite(force: Bool = false) async throws {
        if force || !didBootstrapScheduleSite {
            try await bootstrapScheduleSite()
            didBootstrapScheduleSite = true
        }
    }

    private func bootstrapLKSession() async throws {
        let loginURL = URL(string: "https://lk.dvgups.ru/login?from=%2Fprofile")!
        var loginRequest = URLRequest(url: loginURL)
        loginRequest.httpMethod = "GET"
        DVGUPSBrowserProfile.applyNavigationHeaders(to: &loginRequest)
        loginRequest.timeoutInterval = 15

        _ = try await data(for: loginRequest, acceptStatusCodes: 200...299)
        print("🔐 DVGUPS auth: login page loaded")

        var identifyRequest = URLRequest(url: URL(string: "https://lk.dvgups.ru/api/v1/access/identify")!)
        identifyRequest.httpMethod = "GET"
        DVGUPSBrowserProfile.applyAPIHeaders(
            to: &identifyRequest,
            accept: "*/*",
            referer: loginURL.absoluteString
        )
        identifyRequest.timeoutInterval = 15

        let (_, response) = try await rawData(for: identifyRequest)
        guard response.statusCode == 200 || response.statusCode == 401 else {
            throw APIError.invalidResponse
        }

        guard hasCookie(named: "DO-LK-ID", domainSuffix: "dvgups.ru") else {
            throw APIError.invalidResponse
        }

        print("🔐 DVGUPS auth: session cookie DO-LK-ID is present")
    }

    private func bootstrapScheduleSite() async throws {
        let rootURL = URL(string: "https://dvgups.ru/")!
        var rootRequest = URLRequest(url: rootURL)
        rootRequest.httpMethod = "GET"
        DVGUPSBrowserProfile.applyNavigationHeaders(to: &rootRequest)
        rootRequest.timeoutInterval = 15

        _ = try await data(for: rootRequest, acceptStatusCodes: 200...299)
        print("🔐 DVGUPS auth: main site root loaded")

        let scheduleURL = URL(string: "https://dvgups.ru/public/schedule")!
        var scheduleRequest = URLRequest(url: scheduleURL)
        scheduleRequest.httpMethod = "GET"
        DVGUPSBrowserProfile.applyNavigationHeaders(to: &scheduleRequest)
        scheduleRequest.timeoutInterval = 15

        _ = try await data(for: scheduleRequest, acceptStatusCodes: 200...299)
        print("🔐 DVGUPS auth: public schedule page loaded")
    }

    private func authenticate(with credentials: DVGUPSCredentials) async throws {
        var request = URLRequest(url: URL(string: "https://lk.dvgups.ru/api/v1/access/authenticate")!)
        request.httpMethod = "POST"
        DVGUPSBrowserProfile.applyAPIHeaders(
            to: &request,
            accept: "*/*",
            contentType: "application/json",
            referer: "https://lk.dvgups.ru/login?from=%2Fprofile",
            origin: "https://lk.dvgups.ru"
        )
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "login": credentials.login,
            "password": credentials.password,
            "provider": "password"
        ])

        let data = try await data(for: request, acceptStatusCodes: 200...299)
        let response = try JSONDecoder().decode(DVGUPSAuthResponse.self, from: data)
        guard response.success else {
            throw APIError.invalidCredentials
        }
    }

    private func identifyLKLogin() async throws -> String? {
        var request = URLRequest(url: URL(string: "https://lk.dvgups.ru/api/v1/access/identify")!)
        request.httpMethod = "GET"
        DVGUPSBrowserProfile.applyAPIHeaders(
            to: &request,
            accept: "*/*",
            referer: "https://lk.dvgups.ru/login?from=%2Fprofile"
        )
        request.timeoutInterval = 15

        let (data, response) = try await rawData(for: request)
        switch response.statusCode {
        case 200:
            let payload = try JSONDecoder().decode(DVGUPSAuthResponse.self, from: data)
            guard payload.success else { return nil }
            return payload.data?.user?.login
        case 401, 403:
            return nil
        default:
            throw APIError.invalidResponse
        }
    }

    private func identifyMainSiteLogin() async throws -> String? {
        var request = URLRequest(url: URL(string: "https://dvgups.ru/api/v1/do-lk/identify")!)
        request.httpMethod = "GET"
        DVGUPSBrowserProfile.applyAPIHeaders(
            to: &request,
            accept: "application/json",
            contentType: "application/json",
            referer: "https://dvgups.ru/public/schedule"
        )
        request.timeoutInterval = 15

        let (data, response) = try await rawData(for: request)
        switch response.statusCode {
        case 200:
            let payload = try JSONDecoder().decode(DVGUPSAuthResponse.self, from: data)
            guard payload.success else { return nil }
            return payload.data?.user?.login
        case 401, 403:
            return nil
        default:
            throw APIError.invalidResponse
        }
    }

    private func warmTimetableSession() async throws {
        var request = URLRequest(url: URL(string: "https://dvgups.ru/api/v1/timetable/weeks")!)
        request.httpMethod = "GET"
        DVGUPSBrowserProfile.applyAPIHeaders(
            to: &request,
            accept: "application/json",
            contentType: "application/json",
            referer: "https://dvgups.ru/public/schedule/group"
        )
        request.timeoutInterval = 15

        _ = try await data(for: request, acceptStatusCodes: 200...299)
        print("🔐 DVGUPS auth: timetable session warmed up")
    }

    private func rawData(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, httpResponse)
    }

    private func data(for request: URLRequest, acceptStatusCodes statusCodes: ClosedRange<Int>) async throws -> Data {
        let (data, response) = try await rawData(for: request)
        guard statusCodes.contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                throw APIError.invalidCredentials
            }
            throw APIError.invalidResponse
        }
        return data
    }

    private func hasCookie(named name: String, domainSuffix: String) -> Bool {
        (cookieStorage.cookies ?? []).contains { cookie in
            cookie.name == name && cookie.domain.contains(domainSuffix)
        }
    }
}

@MainActor
final class DVGUPSAuthService: ObservableObject {
    static let shared = DVGUPSAuthService()

    @Published private(set) var status: DVGUPSAuthStatus = .unknown
    @Published private(set) var storedLogin: String?

    private let credentialsStore: DVGUPSCredentialsStore
    private let coordinator: DVGUPSAuthCoordinator
    private var lastStatusRefresh: Date?
    private let statusRefreshInterval: TimeInterval = 180

    init(
        session: URLSession = .shared,
        credentialsStore: DVGUPSCredentialsStore = DVGUPSCredentialsStore()
    ) {
        self.credentialsStore = credentialsStore
        self.coordinator = DVGUPSAuthCoordinator(session: session, credentialsStore: credentialsStore)
        self.storedLogin = (try? credentialsStore.load())?.login
    }

    func refreshStatusIfNeeded() async {
        let shouldRefresh: Bool
        if let lastStatusRefresh {
            shouldRefresh = Date().timeIntervalSince(lastStatusRefresh) >= statusRefreshInterval
        } else {
            shouldRefresh = true
        }

        guard shouldRefresh || status == .unknown else { return }
        await refreshStatus(forceReauthentication: false)
    }

    @discardableResult
    func refreshStatus(forceReauthentication: Bool) async -> DVGUPSAuthStatus {
        storedLogin = (try? credentialsStore.load())?.login
        status = .checking
        let resolvedStatus = await coordinator.resolveStatus(forceReauthentication: forceReauthentication)
        status = resolvedStatus

        if case .authenticated(let login) = resolvedStatus {
            storedLogin = login ?? storedLogin
        }

        lastStatusRefresh = Date()
        return resolvedStatus
    }

    func saveCredentials(login: String, password: String) async throws {
        let trimmedLogin = login.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedPassword = normalizePassword(password)

        guard !trimmedLogin.isEmpty, !normalizedPassword.isEmpty else {
            throw APIError.authenticationRequired
        }

        let newCredentials = DVGUPSCredentials(login: trimmedLogin, password: normalizedPassword)
        let previousCredentials = try credentialsStore.load()

        do {
            try await coordinator.authorize(credentials: newCredentials)
        } catch {
            if let previousCredentials, previousCredentials != newCredentials {
                do {
                    try await coordinator.authorize(credentials: previousCredentials)
                    storedLogin = previousCredentials.login
                    status = .authenticated(login: previousCredentials.login)
                    lastStatusRefresh = Date()
                } catch {
                    storedLogin = previousCredentials.login
                }
            }
            throw normalizeAPIError(error)
        }

        try credentialsStore.save(newCredentials)
        storedLogin = trimmedLogin
        status = .authenticated(login: trimmedLogin)
        lastStatusRefresh = Date()
    }

    func loadStoredCredentials() -> DVGUPSCredentials? {
        try? credentialsStore.load()
    }

    func clearCredentials() async throws {
        try credentialsStore.clear()
        await clearSessionCookies()
        storedLogin = nil
        status = .credentialsMissing
        lastStatusRefresh = nil
    }

    func reauthorizeIfPossible() async throws {
        status = .checking
        do {
            try await coordinator.reauthorizeIfPossible()
            let credentials = try credentialsStore.load()
            storedLogin = credentials?.login
            status = .authenticated(login: credentials?.login)
            lastStatusRefresh = Date()
        } catch {
            let apiError = normalizeAPIError(error)
            status = mapErrorToStatus(apiError)
            lastStatusRefresh = Date()
            throw apiError
        }
    }

    func noteProtectedRequestSucceeded() {
        guard storedLogin != nil || status.isAuthenticated else {
            lastStatusRefresh = Date()
            return
        }

        if !status.isAuthenticated {
            status = .authenticated(login: storedLogin)
        }
        lastStatusRefresh = Date()
    }

    func markAuthorizationRequired() {
        status = .credentialsMissing
        lastStatusRefresh = Date()
    }

    private func clearSessionCookies() async {
        await coordinator.clearSessionCookies()
    }

    private func apiError(for status: DVGUPSAuthStatus) -> APIError {
        switch status {
        case .credentialsMissing:
            return .authenticationRequired
        case .failed:
            return .invalidCredentials
        default:
            return .invalidResponse
        }
    }

    private func mapErrorToStatus(_ error: APIError) -> DVGUPSAuthStatus {
        switch error {
        case .authenticationRequired:
            return .credentialsMissing
        default:
            return .failed(message: error.localizedDescription)
        }
    }

    private func normalizeAPIError(_ error: Error) -> APIError {
        if let apiError = error as? APIError {
            return apiError
        }
        return .networkError(error)
    }

    private func normalizePassword(_ password: String) -> String {
        var normalized = password
        while let lastCharacter = normalized.last, lastCharacter.isNewline {
            normalized.removeLast()
        }
        return normalized
    }
}
