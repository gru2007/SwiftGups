import Foundation

@MainActor
final class AppNewsService: ObservableObject {
    @Published private(set) var feed: AppNewsFeed?
    @Published private(set) var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private let session: URLSession
    private let decoder: JSONDecoder
    
    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = AppNewsService.makeDecoder()
    }
    
    func loadIfNeeded() async {
        if feed != nil { return }
        await refresh(force: false)
    }
    
    func refresh(force: Bool) async {
        guard !isLoading else { return }
        
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        
        guard let url = AppNewsService.feedURL() else {
            errorMessage = "Не задан URL ленты новостей. Укажите APP_NEWS_FEED_URL в Info.plist."
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 25
        request.cachePolicy = force ? .reloadIgnoringLocalCacheData : .useProtocolCachePolicy
        
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                errorMessage = "Ошибка загрузки новостей (сервер)."
                return
            }
            
            let decoded = try decoder.decode(AppNewsFeed.self, from: data)
            self.feed = decoded
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    private static func feedURL() -> URL? {
        guard
            let value = Bundle.main.object(forInfoDictionaryKey: "APP_NEWS_FEED_URL") as? String
        else { return nil }
        
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
    
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            
            if let date = AppNewsService.parseDate(str) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid date: \(str)")
        }
        return decoder
    }
    
    private static func parseDate(_ value: String) -> Date? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        // ISO8601 (updatedAt etc)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: trimmed) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: trimmed) { return d }
        
        // yyyy-MM-dd (news/changelog dates)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = TimeZone(secondsFromGMT: 0)
        df.dateFormat = "yyyy-MM-dd"
        if let d = df.date(from: trimmed) { return d }
        
        return nil
    }
}

