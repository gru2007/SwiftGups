import SwiftUI

struct PromoUniversity: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String
    let emoji: String
    let accent: Color

    static let khabarovsk: [PromoUniversity] = [
        .init(id: "togu", title: "ТОГУ", subtitle: "Тихоокеанский государственный университет", emoji: "🏛️", accent: .purple),
        .init(id: "dvgups", title: "ДВГУПС", subtitle: "Дальневосточный государственный университет путей сообщения", emoji: "🚆", accent: .blue),
        .init(id: "dvgmu", title: "ДВГМУ", subtitle: "Дальневосточный государственный медицинский университет", emoji: "🩺", accent: .red),

        // Можно оставить как “legacy” (официально присоединён к ТОГУ)
        .init(id: "hguep-legacy", title: "ХГУЭП", subtitle: "Экономика и право (в составе ТОГУ; ранее отдельный вуз)", emoji: "📈", accent: .green),

        .init(id: "hgik", title: "ХГИК", subtitle: "Хабаровский государственный институт культуры", emoji: "🎭", accent: .pink),
        .init(id: "dvgafk", title: "ДВГАФК", subtitle: "Дальневосточная государственная академия физической культуры", emoji: "🏅", accent: .teal),

        .init(id: "dvui-mvd", title: "ДВЮИ МВД", subtitle: "Дальневосточный юридический институт МВД России", emoji: "🛡️", accent: .orange),
        .init(id: "vguu-rpa-minjust", title: "ВГУЮ (РПА) – ДВИ", subtitle: "Дальневосточный институт (филиал) ВГУЮ (РПА Минюста России)", emoji: "⚖️", accent: .indigo),

        .init(id: "khpi-fsb", title: "ХПИ ФСБ", subtitle: "Хабаровский пограничный институт ФСБ России", emoji: "🛂", accent: .green),

        .init(id: "dviu-ranepa", title: "ДВИУ РАНХиГС", subtitle: "Дальневосточный институт управления — филиал РАНХиГС", emoji: "🗳️", accent: .orange),
        .init(id: "rgup-feb", title: "РГУП (ДВФ)", subtitle: "Дальневосточный филиал Российского государственного университета правосудия", emoji: "📜", accent: .blue),
    ]
}

enum PromoUniversityResolver {
    static func resolve(from input: String) -> PromoUniversity {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return PromoUniversity(id: "unknown", title: "Ваш вуз", subtitle: "Введите название вуза", emoji: "🎓", accent: .blue)
        }

        let normalized = trimmed.lowercased()
        if let hit = PromoUniversity.khabarovsk.first(where: { uni in
            let t = uni.title.lowercased()
            let s = uni.subtitle.lowercased()
            return normalized.contains(t) || t.contains(normalized) || normalized.contains(s)
        }) {
            return hit
        }

        // Детерминированная “персонализация”: цвет/эмодзи зависят от названия вуза.
        let palette: [Color] = [.blue, .purple, .green, .orange, .pink, .teal, .indigo]
        let emojis = ["🎓", "🏰", "🧠", "⚙️", "🧪", "📚", "🛡️", "🌐"]
        let h = stableHash(normalized)
        let accent = palette[h % palette.count]
        let emoji = emojis[h % emojis.count]

        return PromoUniversity(
            id: "custom-\(h)",
            title: trimmed,
            subtitle: "Хабаровск • GupsShield",
            emoji: emoji,
            accent: accent
        )
    }

    private static func stableHash(_ s: String) -> Int {
        // Простая стабильная хеш-функция (FNV-1a 32-bit) — без зависимости от рандомизации Swift Hashable.
        var hash: UInt32 = 2166136261
        for b in s.utf8 {
            hash ^= UInt32(b)
            hash &*= 16777619
        }
        return Int(hash)
    }
}

