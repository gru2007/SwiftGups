import Foundation

// MARK: - App News (remote JSON)

struct AppNewsFeed: Codable, Hashable {
    var schemaVersion: Int
    var updatedAt: Date?
    var banner: AppNewsBanner?
    var news: [AppNewsItem]
    var changelog: [AppChangelogEntry]
    
    init(
        schemaVersion: Int = 1,
        updatedAt: Date? = nil,
        banner: AppNewsBanner? = nil,
        news: [AppNewsItem] = [],
        changelog: [AppChangelogEntry] = []
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.banner = banner
        self.news = news
        self.changelog = changelog
    }
}

struct AppNewsBanner: Codable, Hashable, Identifiable {
    enum Style: String, Codable, Hashable {
        case info
        case success
        case warning
        case error
    }
    
    struct Link: Codable, Hashable {
        var title: String
        var url: String
    }
    
    var id: String
    var style: Style
    var title: String
    var markdown: String
    var imageUrl: String?
    var link: Link?
    var dismissible: Bool?
}

struct AppNewsItem: Codable, Hashable, Identifiable {
    var id: String
    var date: Date?
    var title: String
    var imageUrl: String?
    var markdown: String
}

struct AppChangelogEntry: Codable, Hashable, Identifiable {
    var id: String { version }
    var version: String
    var date: Date?
    var markdown: String
}

