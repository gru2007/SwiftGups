import SwiftUI

// MARK: - Changelog Manager

class ChangelogManager: ObservableObject {
    @Published var shouldShowChangelog: Bool = false
    
    private let userDefaults = UserDefaults.standard
    private let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    
    init() {
        checkForAppUpdate()
    }
    
    private func checkForAppUpdate() {
        let lastSeenVersion = userDefaults.string(forKey: "last_seen_changelog_version")
        
        // Показываем changelog если:
        // 1. Это первый запуск (lastSeenVersion == nil)
        // 2. Или версия изменилась
        shouldShowChangelog = (lastSeenVersion != currentVersion)
    }
    
    func markChangelogAsSeen() {
        userDefaults.set(currentVersion, forKey: "last_seen_changelog_version")
        shouldShowChangelog = false
    }
    
    func getCurrentVersion() -> String {
        return currentVersion
    }
}

// MARK: - Changelog Entry Model

struct ChangelogEntry {
    let version: String
    let date: String
    let title: String
    let changes: [ChangelogItem]
    let isNew: Bool // Помечает новые обновления
}

struct ChangelogItem {
    let type: ChangelogItemType
    let text: String
}

enum ChangelogItemType {
    case new
    case improvement
    case fix
    case breaking
    
    var icon: String {
        switch self {
        case .new: return "plus.circle.fill"
        case .improvement: return "arrow.up.circle.fill"
        case .fix: return "wrench.and.screwdriver.fill"
        case .breaking: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .new: return .green
        case .improvement: return .blue
        case .fix: return .orange
        case .breaking: return .red
        }
    }
    
    var title: String {
        switch self {
        case .new: return "Новое"
        case .improvement: return "Улучшения"
        case .fix: return "Исправления"
        case .breaking: return "Важно"
        }
    }
}

// MARK: - Changelog Data

extension ChangelogManager {
    static let changelogEntries: [ChangelogEntry] = [
        ChangelogEntry(
            version: "1.0.3",
            date: "11 сентября 2025",
            title: "🎉 Синхронизация изображений с iCloud",
            changes: [
                ChangelogItem(type: .new, text: "Автоматическая синхронизация фотографий домашних заданий через iCloud"),
                ChangelogItem(type: .new, text: "Индикаторы статуса синхронизации для каждого изображения"),
                ChangelogItem(type: .new, text: "Локальный кэш для быстрого доступа без интернета"),
                ChangelogItem(type: .new, text: "Прогресс-бар при загрузке изображений в облако"),
                ChangelogItem(type: .improvement, text: "Полностью переработанный просмотр изображений с плавным зумом до 5x"),
                ChangelogItem(type: .improvement, text: "Улучшенные жесты: зум пинчем, перемещение свайпом, двойной тап для сброса"),
                ChangelogItem(type: .improvement, text: "Отображение метаданных изображений (размер, статус синхронизации)"),
                ChangelogItem(type: .improvement, text: "Оптимизация производительности - значительно ускорена компиляция проекта"),
                ChangelogItem(type: .fix, text: "Исправлены ошибки с типами данных в жестах SwiftUI"),
                ChangelogItem(type: .fix, text: "Исправлена совместимость с CloudKit для отношений SwiftData"),
                ChangelogItem(type: .fix, text: "Улучшена стабильность при работе с большим количеством изображений")
            ],
            isNew: true
        ),
    ]
}

// MARK: - Changelog View

struct ChangelogView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var changelogManager = ChangelogManager()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // Header
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Что нового")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                
                                Text("SwiftGups v\(changelogManager.getCurrentVersion())")
                                    .font(.title3)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            // App Icon
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    LinearGradient(
                                        colors: [.blue, .cyan],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 80, height: 80)
                                .overlay(
                                    Text("SG")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.white)
                                )
                                .shadow(color: .blue.opacity(0.3), radius: 8, x: 0, y: 4)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 20)
                    .padding(.bottom, 32)
                    
                    // Changelog entries
                    LazyVStack(spacing: 32) {
                        ForEach(ChangelogManager.changelogEntries.indices, id: \.self) { index in
                            let entry = ChangelogManager.changelogEntries[index]
                            ChangelogEntryView(entry: entry)
                                .padding(.horizontal, 24)
                        }
                    }
                    
                    // Footer
                    VStack(spacing: 16) {
                        Divider()
                        
                        Text("Нравится приложение? Оставьте отзыв в App Store!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        HStack(spacing: 16) {
                            Button {
                                if let url = URL(string: "https://apps.apple.com/us/app/swiftgups/id6751450752?action=write-review") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "star.fill")
                                    Text("Оценить")
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.blue)
                                .cornerRadius(20)
                            }
                            
                            Button {
                                if let url = URL(string: "https://artemevkhv.t.me") {
                                    UIApplication.shared.open(url)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: "questionmark.circle")
                                    Text("Поддержка")
                                }
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(.blue)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 10)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(20)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Готово") {
                        changelogManager.markChangelogAsSeen()
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

// MARK: - Changelog Entry View

struct ChangelogEntryView: View {
    let entry: ChangelogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Version header
            HStack(alignment: .center, spacing: 12) {
                HStack(spacing: 8) {
                    Text("v\(entry.version)")
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    
                    if entry.isNew {
                        Text("НОВОЕ")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                }
                
                Spacer()
                
                Text(entry.date)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Title
            Text(entry.title)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            
            // Changes
            VStack(alignment: .leading, spacing: 12) {
                ForEach(groupedChanges.keys.sorted(by: { lhs, rhs in
                    let order: [ChangelogItemType] = [.new, .improvement, .fix, .breaking]
                    return order.firstIndex(of: lhs) ?? 0 < order.firstIndex(of: rhs) ?? 0
                }), id: \.self) { type in
                    if let changes = groupedChanges[type] {
                        ChangelogSectionView(type: type, changes: changes)
                    }
                }
            }
        }
        .padding(.vertical, 20)
        .padding(.horizontal, 20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemGray6).opacity(0.5))
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
        )
    }
    
    private var groupedChanges: [ChangelogItemType: [ChangelogItem]] {
        Dictionary(grouping: entry.changes, by: { $0.type })
    }
}

// MARK: - Changelog Section View

struct ChangelogSectionView: View {
    let type: ChangelogItemType
    let changes: [ChangelogItem]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Section header
            HStack(spacing: 8) {
                Image(systemName: type.icon)
                    .font(.caption)
                    .foregroundColor(type.color)
                
                Text(type.title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(type.color)
            }
            
            // Changes list
            VStack(alignment: .leading, spacing: 6) {
                ForEach(changes.indices, id: \.self) { index in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(type.color.opacity(0.3))
                            .frame(width: 6, height: 6)
                            .padding(.top, 6)
                        
                        Text(changes[index].text)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                        
                        Spacer()
                    }
                }
            }
        }
    }
}

// MARK: - Changelog Sheet Modifier

extension View {
    func changelogSheet() -> some View {
        modifier(ChangelogSheetModifier())
    }
}

struct ChangelogSheetModifier: ViewModifier {
    @StateObject private var changelogManager = ChangelogManager()
    
    func body(content: Content) -> some View {
        content
            .sheet(isPresented: $changelogManager.shouldShowChangelog) {
                ChangelogView()
            }
    }
}

#Preview {
    ChangelogView()
}
