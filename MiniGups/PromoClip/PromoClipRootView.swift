import SwiftUI
import UIKit
import WebKit

struct PromoClipRootView: View {
    let invocationURL: URL?

    var body: some View {
        TabView {
            PromoHomeView(invocationURL: invocationURL)
                .tabItem { Label("Сервер", systemImage: "cube.fill") }

            PromoMapView(invocationURL: invocationURL)
                .tabItem { Label("Карта", systemImage: "map.fill") }

            PromoIdCardGeneratorView()
                .tabItem { Label("ID", systemImage: "person.crop.rectangle") }
        }
        .tint(.green)
    }
}

private struct PromoHomeView: View {
    let invocationURL: URL?

    @State private var showRegister = false

    private var registerURL: URL { PromoLinks.registrationURL(from: invocationURL) }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    PromoHeroCard()

                    PromoFeatureGrid()

                    PromoCTAButton(
                        title: "Забронировать никнейм",
                        subtitle: "Откроем регистрацию в приложении",
                        systemImage: "person.badge.plus",
                        tint: .green
                    ) {
                        showRegister = true
                    }

                    PromoSecondaryInfoCard()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(
                LinearGradient(
                    colors: [Color.green.opacity(0.10), Color.blue.opacity(0.08), Color(.systemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("GupsShield")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showRegister) {
            SafariView(url: registerURL)
        }
    }
}

private struct PromoMapView: View {
    let invocationURL: URL?

    @State private var showMap = false

    private var mapURL: URL { PromoLinks.mapURL(from: invocationURL) }

    var body: some View {
        NavigationView {
            PromoMapContent(mapURL: mapURL, showMap: $showMap)
                .fullScreenCover(isPresented: $showMap) {
                    SafariView(url: mapURL)
                }
                .background(
                    LinearGradient(
                        colors: [Color.green.opacity(0.10), Color.blue.opacity(0.08), Color(.systemBackground)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                )
                .navigationTitle("3D карта (Прошлый Сезон)")
                .navigationBarTitleDisplayMode(NavigationBarItem.TitleDisplayMode.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button {
                            UIApplication.shared.open(mapURL)
                        } label: {
                            Image(systemName: "safari")
                        }
                        .accessibilityLabel(Text("Открыть в Safari"))
                    }
                }
        }
    }
}

@ViewBuilder
private func PromoMapContent(mapURL: URL, showMap: Binding<Bool>) -> some View {
    if #available(iOS 26.0, *) {
        PromoMapWebView(url: mapURL)
    } else {
        PromoMapFallback(mapURL: mapURL, showMap: showMap)
    }
}

/// Карта через новый WebKit for SwiftUI (iOS 26+): нативный WebView без UIKit-обёртки.
@available(iOS 26.0, *)
private struct PromoMapWebView: View {
    let url: URL

    @State private var page = WebPage()

    var body: some View {
        ZStack(alignment: .top) {
            WebView(page)
                .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 10) {

                if page.estimatedProgress < 1.0 {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Загрузка карты…")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                    .padding(14)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                Spacer(minLength: 0)
            }
        }
        .onAppear {
            page.load(URLRequest(url: url))
        }
    }
}

/// Fallback для iOS 17–25: кнопка открывает карту в SFSafariViewController.
private struct PromoMapFallback: View {
    let mapURL: URL
    @Binding var showMap: Bool

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PromoCTAButton(
                    title: "Открыть 3D карту",
                    subtitle: "Карта откроется в приложении",
                    systemImage: "map.fill",
                    tint: .green
                ) {
                    showMap = true
                }
            }
            .padding(16)
        }
    }
}


private struct PromoHeroCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(
                            LinearGradient(
                                colors: [Color.green, Color.blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 64, height: 64)
                        .shadow(color: .green.opacity(0.25), radius: 14, x: 0, y: 8)

                    Image(systemName: "cube.fill")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Межвузовский Minecraft‑сервер")
                        .font(.headline)
                        .fontWeight(.bold)

                    Text("Towny • Community‑driven экономика • Точки захвата • Кланы")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()
            }

            Divider().opacity(0.6)

            HStack(spacing: 12) {
                PromoBadge(text: "PC + Phone", systemImage: "iphone.and.arrow.forward")
                PromoBadge(text: "Season‑based", systemImage: "clock.arrow.circlepath")
                PromoBadge(text: "Towny", systemImage: "building.2.fill")
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
        )
    }
}

private struct PromoBadge: View {
    let text: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .foregroundColor(.green)
            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 999)
                .fill(Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 999)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

private struct PromoFeatureGrid: View {
    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            PromoFeatureCard(
                title: "Towny",
                subtitle: "Города, регионы, союзы и политика.",
                systemImage: "building.2.fill",
                tint: .green
            )
            PromoFeatureCard(
                title: "Экономика",
                subtitle: "Рынок, обмены, профессии, налоги — игроки решают.",
                systemImage: "banknote.fill",
                tint: .blue
            )
            PromoFeatureCard(
                title: "Точки захвата",
                subtitle: "События, контроль территорий, награды.",
                systemImage: "flag.checkered.2.crossed",
                tint: .orange
            )
            PromoFeatureCard(
                title: "Комьюнити",
                subtitle: "Правила и решения — через игроков и голосования.",
                systemImage: "person.3.fill",
                tint: .purple
            )
        }
    }
}

private struct PromoFeatureCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .foregroundColor(tint)
                Text(title)
                    .font(.headline)
                    .fontWeight(.semibold)
                Spacer()
            }

            Text(subtitle)
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
}

private struct PromoCTAButton: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 44, height: 44)
                    Image(systemName: systemImage)
                        .foregroundColor(tint)
                        .font(.system(size: 18, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct PromoSecondaryInfoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Подключение", systemImage: "link")
                .font(.headline)

            Text("Для ПК понадобится наш лаунчер и аккаунт. Играть можно и с телефона, и с ПК.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text("minecraft.r-artemev.ru")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(RoundedRectangle(cornerRadius: 999).fill(Color(.systemGray6)))

                Spacer()

                Text("© 2026 ArtemevSoft")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
    }
}

