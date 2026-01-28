import SwiftUI

/// Хост для баннера из AppNews: показывает баннер, если он dismissible и не был скрыт
/// (скрытие запоминается до изменения контента на S3).
struct AppNewsBannerHost: View {
    let banner: AppNewsBanner
    
    // Новая логика: ключ от контента (меняется при изменении текста/линка/картинки и т.д.)
    @AppStorage("appNewsDismissedBannerKey") private var dismissedBannerKey: String = ""
    
    // Legacy: чтобы не ломать уже скрытые баннеры в старых версиях.
    @AppStorage("appNewsDismissedBannerId") private var dismissedBannerId: String = ""
    
    var body: some View {
        guard shouldShow else { return AnyView(EmptyView()) }
        return AnyView(
            AppNewsBannerView(banner: banner) {
                dismiss()
            }
        )
    }
    
    private var shouldShow: Bool {
        let isDismissible = banner.dismissible ?? true
        if !isDismissible { return true }
        
        let key = AppNewsBannerDismissKey.make(for: banner)
        return dismissedBannerKey != key && dismissedBannerId != banner.id
    }
    
    private func dismiss() {
        dismissedBannerKey = AppNewsBannerDismissKey.make(for: banner)
        dismissedBannerId = banner.id
    }
}

