import SwiftUI

struct AppNewsView: View {
    @StateObject private var service = AppNewsService()
    @State private var selectedNewsItem: AppNewsItem?
    @State private var selectedSection: Section = .news
    
    enum Section: String, CaseIterable {
        case news = "Новости"
        case changelog = "Changelog"
    }
    
    var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $selectedSection) {
                ForEach(Section.allCases, id: \.self) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            
            content
        }
        .task { await service.loadIfNeeded() }
        .refreshable { await service.refresh(force: true) }
        .sheet(item: $selectedNewsItem) { item in
            AppNewsDetailSheet(item: item)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    Task { await service.refresh(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(service.isLoading)
            }
        }
    }
    
    @ViewBuilder
    private var content: some View {
        if let error = service.errorMessage {
            VStack(spacing: 16) {
                ErrorBanner(message: error) { service.errorMessage = nil }
                    .padding(.horizontal)
                
                Spacer()
            }
        } else if service.feed == nil && service.isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Загрузка…")
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let feed = service.feed {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if let banner = feed.banner {
                        AppNewsBannerHost(banner: banner)
                            .padding(.horizontal)
                            .padding(.top, 8)
                    }
                    
                    if let updatedAt = feed.updatedAt {
                        HStack {
                            Text("Обновлено: \(updatedAt, format: .dateTime.day().month().year().hour().minute())")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal)
                    }
                    
                    switch selectedSection {
                    case .news:
                        if feed.news.isEmpty {
                            AppNewsEmptyState(title: "Новостей пока нет", subtitle: "Загляните позже или потяните вниз, чтобы обновить.")
                                .padding(.top, 40)
                        } else {
                            ForEach(feed.news) { item in
                                AppNewsCard(item: item) {
                                    selectedNewsItem = item
                                }
                                .padding(.horizontal)
                            }
                        }
                    case .changelog:
                        if feed.changelog.isEmpty {
                            AppNewsEmptyState(title: "Changelog пуст", subtitle: "Добавьте записи в JSON, и они появятся здесь.")
                                .padding(.top, 40)
                        } else {
                            ForEach(feed.changelog) { entry in
                                AppChangelogCard(entry: entry)
                                    .padding(.horizontal)
                            }
                        }
                    }
                    
                    Spacer(minLength: 24)
                }
                .padding(.vertical, 8)
            }
        } else {
            AppNewsEmptyState(
                title: "Новости не загружены",
                subtitle: "Проверьте APP_NEWS_FEED_URL и сеть."
            )
            .padding(.top, 40)
        }
    }
}

// MARK: - Components

private struct AppNewsCard: View {
    let item: AppNewsItem
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                if let imageUrl = item.imageUrl, let url = URL(string: imageUrl) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(maxHeight: 160)
                                .clipped()
                                .cornerRadius(12)
                        case .empty:
                            Rectangle()
                                .fill(Color.gray.opacity(0.15))
                                .overlay(ProgressView())
                                .frame(maxHeight: 160)
                                .cornerRadius(12)
                        case .failure:
                            EmptyView()
                        @unknown default:
                            EmptyView()
                        }
                    }
                }
                
                Text(item.title)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.leading)
                
                if let date = item.date {
                    Text(date, format: .dateTime.day().month().year())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct AppChangelogCard: View {
    let entry: AppChangelogEntry
    @State private var expanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(entry.version)
                    .font(.headline)
                Spacer()
                if let date = entry.date {
                    Text(date, format: .dateTime.day().month().year())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            if expanded {
                AppMarkdownText(markdown: entry.markdown)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Button(expanded ? "Свернуть" : "Показать") {
                withAnimation(.easeInOut(duration: 0.2)) { expanded.toggle() }
            }
            .font(.caption.weight(.semibold))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 2)
        )
    }
}

private struct AppNewsDetailSheet: View {
    let item: AppNewsItem
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let imageUrl = item.imageUrl, let url = URL(string: imageUrl) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                                    .frame(maxHeight: 260)
                                    .clipped()
                                    .cornerRadius(16)
                            case .empty:
                                Rectangle()
                                    .fill(Color.gray.opacity(0.15))
                                    .overlay(ProgressView())
                                    .frame(maxHeight: 260)
                                    .cornerRadius(16)
                            case .failure:
                                EmptyView()
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                    
                    Text(item.title)
                        .font(.title2.weight(.bold))
                    
                    if let date = item.date {
                        Text(date, format: .dateTime.day().month().year())
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Divider()
                    
                    AppMarkdownText(markdown: item.markdown)
                        .font(.body)
                }
                .padding(16)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}

private struct AppNewsEmptyState: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "newspaper")
                .font(.system(size: 44))
                .foregroundColor(.secondary.opacity(0.6))
            
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity)
    }
}

