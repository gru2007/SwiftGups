import Foundation
import SwiftUI

enum MiniGupsExperience: Equatable {
    /// Текущий (обычный) App Clip: расписание (домены `clipcards.*` и дефолт).
    case schedule
    /// Промо-кампания для GupsShield (домен `gups.*`).
    case gupsPromo(invocationURL: URL?)
}

private enum MiniGupsExperienceRouter {
    static func route(for url: URL?) -> MiniGupsExperience {
        guard let host = url?.host?.lowercased() else { return .schedule }

        let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        switch normalizedHost {
        case "gups.r-artemev.ru":
            return .gupsPromo(invocationURL: url)
        case "clipcards.r-artemev.ru":
            return .schedule
        default:
            return .schedule
        }
    }
}

struct MiniGupsRootView: View {
    @State private var experience: MiniGupsExperience?

    var body: some View {
        SwiftUI.Group {
            switch experience {
            case .schedule:
                ContentView()
            case .gupsPromo(let url):
                PromoClipRootView(invocationURL: url)
            case .none:
                MiniGupsLaunchPlaceholder()
            }
        }
        .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
            experience = MiniGupsExperienceRouter.route(for: activity.webpageURL)
        }
        .onOpenURL { url in
            experience = MiniGupsExperienceRouter.route(for: url)
        }
        .task {
            // Если App Clip запущен без invocation URL — считаем это "обычным" сценарием (расписание).
            try? await Task.sleep(nanoseconds: 150_000_000)
            if experience == nil {
                experience = .schedule
            }
        }
    }
}

private struct MiniGupsLaunchPlaceholder: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.blue.opacity(0.12), Color.purple.opacity(0.10), Color(.systemBackground)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 14) {
                ProgressView()
                Text("Загрузка…")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
        }
    }
}

