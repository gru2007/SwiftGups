import Foundation
import CryptoKit

enum AppNewsBannerDismissKey {
    static func make(for banner: AppNewsBanner) -> String {
        let raw = [
            banner.id,
            banner.style.rawValue,
            banner.title,
            banner.markdown,
            banner.imageUrl ?? "",
            banner.link?.title ?? "",
            banner.link?.url ?? "",
            String(banner.dismissible ?? true)
        ].joined(separator: "\n")
        
        let digest = SHA256.hash(data: Data(raw.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

