import SwiftUI

struct AppNewsBannerView: View {
    let banner: AppNewsBanner
    let dismiss: () -> Void
    
    @Environment(\.openURL) private var openURL
    
    private var background: Color {
        switch banner.style {
        case .info: return Color.blue.opacity(0.12)
        case .success: return Color.green.opacity(0.12)
        case .warning: return Color.orange.opacity(0.14)
        case .error: return Color.red.opacity(0.12)
        }
    }
    
    private var border: Color {
        switch banner.style {
        case .info: return Color.blue.opacity(0.25)
        case .success: return Color.green.opacity(0.25)
        case .warning: return Color.orange.opacity(0.28)
        case .error: return Color.red.opacity(0.25)
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                    .font(.title3)
                
                VStack(alignment: .leading, spacing: 6) {
                    Text(banner.title)
                        .font(.headline)
                    
                    AppMarkdownText(markdown: banner.markdown)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if banner.dismissible ?? true {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(6)
                            .background(Circle().fill(Color(.systemBackground).opacity(0.7)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Скрыть баннер")
                }
            }
            
            if let imageUrl = banner.imageUrl, let url = URL(string: imageUrl) {
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
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 80)
                    case .failure:
                        EmptyView()
                    @unknown default:
                        EmptyView()
                    }
                }
            }
            
            if let link = banner.link, let url = URL(string: link.url) {
                Button(link.title) {
                    openURL(url)
                }
                .font(.subheadline.weight(.semibold))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(background)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(border, lineWidth: 1)
                )
        )
    }
    
    private var iconName: String {
        switch banner.style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.seal.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }
    
    private var iconColor: Color {
        switch banner.style {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

