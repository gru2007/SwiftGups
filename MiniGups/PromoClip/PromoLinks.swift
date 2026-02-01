import Foundation

enum PromoLinks {
    static let siteBase = URL(string: "https://gups.r-artemev.ru")!

    static func registrationURL(from invocationURL: URL?) -> URL {
        // Позволяем сайту передать точный URL через query параметр, чтобы не приходилось менять приложение.
        if let url = queryURL(invocationURL, keys: ["register_url", "registerUrl"]) {
            return url
        }

        // Фолбэк: экран регистрации на сайте (Azuriom).
        let registerPath = URL(string: "https://gups.r-artemev.ru/user/register")!
        var components = URLComponents(url: registerPath, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "utm_source", value: "appclip"))
        items.append(URLQueryItem(name: "utm_campaign", value: "gupsshield"))
        components?.queryItems = items
        return components?.url ?? registerPath
    }

    static func mapURL(from invocationURL: URL?) -> URL {
        if let url = queryURL(invocationURL, keys: ["map_url", "mapUrl"]) {
            return url
        }

        // Фолбэк: веб-карта прошлого сезона.
        let mapBase = URL(string: "https://webmap.website.twcstorage.ru")!
        var components = URLComponents(url: mapBase, resolvingAgainstBaseURL: false)
        var items = components?.queryItems ?? []
        items.append(URLQueryItem(name: "utm_source", value: "appclip"))
        components?.queryItems = items
        return components?.url ?? mapBase
    }

    private static func queryURL(_ url: URL?, keys: [String]) -> URL? {
        guard let url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return nil }

        for k in keys {
            if let value = items.first(where: { $0.name == k })?.value,
               let parsed = URL(string: value) {
                return parsed
            }
        }
        return nil
    }
}

