import SwiftUI
import UIKit

/// Проверка эндпоинтов ДВГУПС прямо с устройства.
///
/// Нужна, потому что «Неверный формат ответа сервера» на экране расписания
/// не говорит ничего: неизвестно, какой запрос упал и с каким кодом. Экран
/// прогоняет все запросы, которыми пользуется приложение, и показывает по
/// каждому код ответа, время, размер и начало тела. Отчёт можно скопировать
/// и отправить целиком.
struct APIDiagnosticsView: View {
    /// Группа пользователя — по ней проверяем сам запрос расписания.
    let groupId: String
    let groupName: String

    @Environment(\.dismiss) private var dismiss
    @State private var probes: [APIProbeResult] = []
    @State private var isRunning = false
    @State private var didCopy = false

    private let runner = APIDiagnosticsRunner()

    var body: some View {
        NavigationView {
            List {
                Section {
                    if probes.isEmpty && !isRunning {
                        Text("Проверка пройдёт по всем запросам, которыми приложение получает расписание, и покажет ответ сервера по каждому.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        Task { await run() }
                    } label: {
                        HStack {
                            if isRunning {
                                ProgressView()
                                    .controlSize(.small)
                                Text("Проверяем…")
                            } else {
                                Image(systemName: "stethoscope")
                                Text(probes.isEmpty ? "Запустить проверку" : "Повторить проверку")
                            }
                            Spacer()
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .disabled(isRunning)
                }

                if !probes.isEmpty {
                    Section("Результаты") {
                        ForEach(probes) { probe in
                            probeRow(probe)
                        }
                    }

                    Section {
                        Button {
                            UIPasteboard.general.string = report
                            didCopy = true
                        } label: {
                            HStack {
                                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                Text(didCopy ? "Отчёт скопирован" : "Скопировать отчёт")
                                Spacer()
                            }
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                        }
                    } footer: {
                        Text("В отчёте только адреса запросов и ответы сервера. Логин, пароль и cookie в него не попадают.")
                    }
                }
            }
            .navigationTitle("Диагностика")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") { dismiss() }
                }
            }
        }
    }

    private func probeRow(_ probe: APIProbeResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: probe.isSuccess ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundStyle(probe.isSuccess ? Color.green : Color.red)

                Text(probe.title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text(probe.statusText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Text(probe.path)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(probe.detail)
                .font(.caption2.monospaced())
                .foregroundStyle(probe.isSuccess ? Color.secondary : Color.red)
                .lineLimit(6)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var report: String {
        var lines = ["SwiftGups — диагностика API", "Группа: \(groupName) (\(groupId))", ""]
        lines += probes.map { probe in
            """
            \(probe.isSuccess ? "OK " : "FAIL") \(probe.title)
            \(probe.path)
            \(probe.statusText) — \(probe.detail)
            """
        }
        return lines.joined(separator: "\n\n")
    }

    private func run() async {
        isRunning = true
        didCopy = false
        probes = []

        for await probe in runner.run(groupId: groupId) {
            probes.append(probe)
        }

        isRunning = false
    }
}

// MARK: - Результат одной проверки

struct APIProbeResult: Identifiable {
    let id = UUID()
    let title: String
    let path: String
    let statusCode: Int?
    let duration: TimeInterval
    let detail: String
    let isSuccess: Bool

    var statusText: String {
        let time = String(format: "%.1f с", duration)
        guard let statusCode else { return "нет ответа · \(time)" }
        return "HTTP \(statusCode) · \(time)"
    }
}

// MARK: - Прогон проверок

/// Ходит по эндпоинтам напрямую, без слоёв приложения.
///
/// Специально мимо `DVGUPSAPIClient`: задача — увидеть сырой ответ сервера,
/// а не то, во что его превратит разбор.
struct APIDiagnosticsRunner {
    private let baseURL = "https://dvgups.ru"
    private let timeout: TimeInterval = 15

    /// Набор заголовков запроса.
    ///
    /// Сервер режет запросы без браузерного User-Agent: отдаёт 403 и HTML-страницу
    /// вместо JSON. Поэтому «как приложение» — рабочий набор, а вариант без
    /// User-Agent оставлен одной контрольной строкой, чтобы это было видно.
    enum HeaderStyle {
        /// Как шлёт `DVGUPSAPIClient`.
        case app
        /// Без User-Agent — URLSession подставляет свой.
        case noUserAgent

        var title: String {
            switch self {
            case .app: return "заголовки приложения"
            case .noUserAgent: return "без User-Agent"
            }
        }
    }

    func run(groupId: String) -> AsyncStream<APIProbeResult> {
        // Тот же понедельник, с которого начинает запрашивать приложение.
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: Date())
        let daysFromMonday = (weekday + 5) % 7
        let weekStart = calendar.date(byAdding: .day, value: -daysFromMonday, to: Date()) ?? Date()
        let startDate = DateFormatter.serverDateFormatter.string(from: weekStart)

        var checks: [(String, String, HeaderStyle)] = [
            ("Учебные недели", "/api/v1/timetable/weeks", .app),
            ("Справочник групп", "/api/v1/timetable/groups/options?page=1&limit=5", .app),
            ("Поиск группы", "/api/v1/timetable/groups/options?page=1&limit=5&q=%D0%91%D0%9E", .app),
            ("Институты (старый API)", "/api/v1/timetable/faculties", .app)
        ]

        if !groupId.isEmpty {
            // Сервер переехал на snake_case; camelCase проверяем следом, чтобы
            // видеть, какой вариант принимает текущий деплой.
            checks.append((
                "Расписание (snake_case)",
                "/api/v1/timetable/schedule?schedule_type=gr&parameter=\(groupId)&days=7&start_date=\(startDate)",
                .app
            ))
            checks.append((
                "Расписание (camelCase)",
                "/api/v1/timetable/schedule?scheduleType=gr&parameter=\(groupId)&days=7&startDate=\(startDate)",
                .app
            ))
        }

        // Контрольная строка: показывает, что без User-Agent приходит 403.
        checks.append(("Контроль WAF", "/api/v1/timetable/weeks", .noUserAgent))

        return AsyncStream { continuation in
            Task {
                for (title, path, style) in checks {
                    continuation.yield(await probe(title: title, path: path, style: style))
                }
                continuation.finish()
            }
        }
    }

    private func probe(title: String, path: String, style: HeaderStyle) async -> APIProbeResult {
        let fullTitle = "\(title) — \(style.title)"

        guard let url = URL(string: baseURL + path) else {
            return APIProbeResult(
                title: fullTitle, path: path, statusCode: nil, duration: 0,
                detail: "Не удалось собрать URL", isSuccess: false
            )
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = timeout
        apply(style, to: &request)

        let started = Date()

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let elapsed = Date().timeIntervalSince(started)

            guard let http = response as? HTTPURLResponse else {
                return APIProbeResult(
                    title: fullTitle, path: path, statusCode: nil, duration: elapsed,
                    detail: "Ответ не по HTTP", isSuccess: false
                )
            }

            let ok = (200...299).contains(http.statusCode)
            return APIProbeResult(
                title: fullTitle,
                path: path,
                statusCode: http.statusCode,
                duration: elapsed,
                detail: summary(of: data, isSuccess: ok),
                isSuccess: ok
            )
        } catch {
            return APIProbeResult(
                title: fullTitle,
                path: path,
                statusCode: nil,
                duration: Date().timeIntervalSince(started),
                detail: error.localizedDescription,
                isSuccess: false
            )
        }
    }

    private func apply(_ style: HeaderStyle, to request: inout URLRequest) {
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://dvgups.ru/public/schedule/group", forHTTPHeaderField: "Referer")

        guard style == .app else { return }

        request.setValue(DVGUPSBrowserProfile.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue(DVGUPSBrowserProfile.acceptLanguage, forHTTPHeaderField: "Accept-Language")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")
        request.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        request.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        request.setValue("u=3, i", forHTTPHeaderField: "Priority")
    }

    /// Короткая выжимка тела: сколько элементов пришло или начало ответа.
    private func summary(of data: Data, isSuccess: Bool) -> String {
        let text = String(data: data, encoding: .utf8) ?? "<не UTF-8>"

        guard isSuccess else {
            // Тело ошибки показываем целиком: в нём и лежит объяснение
            // («schedule_type must be one of...»), обрезать его нельзя.
            return "\(data.count) Б · \(text.prefix(1200))"
        }

        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let array = object["data"] as? [Any] {
                return "\(data.count) Б · элементов: \(array.count)"
            }
            if let nested = object["data"] as? [String: Any],
               let items = nested["items"] as? [Any] {
                let hasMore = nested["has_more"] as? Bool
                return "\(data.count) Б · items: \(items.count)\(hasMore == true ? ", есть ещё страницы" : "")"
            }
        }

        return "\(data.count) Б · \(text.prefix(160))"
    }
}
