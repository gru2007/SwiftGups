import SwiftUI
import UIKit

struct PromoIdCardGeneratorView: View {
    @State private var universityText: String = "ДВГУПС"
    @State private var generatedImage: UIImage?
    @State private var showShare = false

    private var university: PromoUniversity {
        PromoUniversityResolver.resolve(from: universityText)
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    PromoIdCardPreview(university: university)
                        .padding(.top, 6)

                    VStack(alignment: .leading, spacing: 10) {
                        Label("Вуз", systemImage: "building.columns.fill")
                            .font(.headline)

                        TextField("Например: ДВГУПС, ТОГУ…", text: $universityText)
                            .textFieldStyle(.roundedBorder)

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(PromoUniversity.khabarovsk) { uni in
                                    Button {
                                        universityText = uni.title
                                    } label: {
                                        HStack(spacing: 8) {
                                            Text(uni.emoji)
                                            Text(uni.title)
                                                .fontWeight(.semibold)
                                        }
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 8)
                                        .background(
                                            RoundedRectangle(cornerRadius: 999)
                                                .fill(Color(.systemGray6))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 999)
                                                .stroke(Color(.systemGray4), lineWidth: 1)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 2)
                        }

                        Text("Мы первыми поддерживаем вузы Хабаровска — дальше будет больше.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
                    )

                    HStack(spacing: 12) {
                        Button {
                            generatedImage = PromoIdCardRenderer.render(university: university)
                            showShare = (generatedImage != nil)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "sparkles")
                                Text("Сгенерировать картинку")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(RoundedRectangle(cornerRadius: 14).fill(university.accent))
                            .foregroundColor(.white)
                        }

                        Button {
                            universityText = "ДВГУПС"
                        } label: {
                            Text("Сброс")
                                .frame(width: 84, height: 46)
                                .background(RoundedRectangle(cornerRadius: 14).fill(Color(.systemGray6)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
            .background(
                LinearGradient(
                    colors: [university.accent.opacity(0.12), Color(.systemBackground)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            )
            .navigationTitle("ID‑карта")
            .navigationBarTitleDisplayMode(.inline)
        }
        .sheet(isPresented: $showShare) {
            if let img = generatedImage {
                PromoShareSheet(activityItems: [img])
            } else {
                Text("Не удалось сгенерировать картинку.")
                    .padding()
            }
        }
    }
}

private enum PromoIdCardRenderer {
    @MainActor
    static func render(university: PromoUniversity) -> UIImage? {
        let view = PromoIdCardPreview(university: university)
            .frame(width: 380)
            .padding(16)
            .background(Color(.systemBackground))

        let renderer = ImageRenderer(content: view)
        renderer.scale = UIScreen.main.scale
        return renderer.uiImage
    }
}

private struct PromoIdCardPreview: View {
    let university: PromoUniversity

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22)
                .fill(
                    LinearGradient(
                        colors: [
                            university.accent.opacity(0.95),
                            university.accent.opacity(0.55),
                            Color(.systemBackground).opacity(0.90),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 22)
                        .stroke(Color.white.opacity(0.22), lineWidth: 1)
                )
                .shadow(color: university.accent.opacity(0.18), radius: 16, x: 0, y: 10)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    HStack(spacing: 10) {
                        Text(university.emoji)
                            .font(.system(size: 28))

                        VStack(alignment: .leading, spacing: 2) {
                            Text("GupsShield")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundColor(.white.opacity(0.9))
                            Text("Университетский пропуск")
                                .font(.headline)
                                .fontWeight(.bold)
                                .foregroundColor(.white)
                        }
                    }

                    Spacer()

                    Text("SEASON 1")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(RoundedRectangle(cornerRadius: 999).fill(Color.black.opacity(0.18)))
                        .foregroundColor(.white.opacity(0.9))
                }

                Spacer(minLength: 6)

                VStack(alignment: .leading, spacing: 6) {
                    Text(university.title)
                        .font(.title3)
                        .fontWeight(.heavy)
                        .foregroundColor(.white)
                        .lineLimit(1)

                    Text(university.subtitle)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.85))
                        .lineLimit(2)

                    HStack(spacing: 10) {
                        Label("Towny", systemImage: "building.2.fill")
                        Label("Economy", systemImage: "bitcoinsign.circle.fill")
                        Label("PvP zones", systemImage: "scope")
                    }
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.9))
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack {
                    Text("gups.r-artemev.ru")
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.85))
                    Spacer()
                    Text("App Clip")
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.9))
                }
            }
            .padding(16)
        }
        .frame(height: 220)
        .overlay(
            PromoPixelOverlay()
                .clipShape(RoundedRectangle(cornerRadius: 22))
        )
    }
}

private struct PromoPixelOverlay: View {
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            Canvas { ctx, _ in
                let cell: CGFloat = 10
                let cols = Int(size.width / cell)
                let rows = Int(size.height / cell)

                for r in 0..<rows {
                    for c in 0..<cols {
                        // Лёгкий пиксельный шум в стиле minecraft, но очень деликатно.
                        let v = (r * 131 + c * 73) % 19
                        guard v == 0 || v == 3 else { continue }
                        let rect = CGRect(x: CGFloat(c) * cell, y: CGFloat(r) * cell, width: cell, height: cell)
                        ctx.fill(Path(rect), with: .color(.white.opacity(v == 0 ? 0.06 : 0.03)))
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }
}

private struct PromoShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

