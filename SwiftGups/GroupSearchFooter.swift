import SwiftUI

/// Подвал списка групп: состояние серверного поиска по всему вузу.
///
/// Новый API ищет группу по всему справочнику (`/groups/options?q=`), поэтому
/// в списке появляются группы других институтов — об этом и говорит подвал.
struct GroupSearchFooter: View {
    @ObservedObject var scheduleService: ScheduleService
    let searchText: String

    /// HIG: минимальная область нажатия — 44×44 pt.
    private let minimumTapTarget: CGFloat = 44

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        // `SwiftUI.Group` — в проекте есть своя модель `Group`.
        SwiftUI.Group {
            if query.count >= 2 {
                if scheduleService.isSearchingGroups {
                    searchingLabel
                } else if scheduleService.groupSearchHasMore {
                    loadMoreButton
                }
            }
        }
    }

    private var searchingLabel: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)

            Text("Ищем группу по всему вузу…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        // Спиннер и подпись — один элемент для VoiceOver, а не два подряд.
        .accessibilityElement(children: .combine)
        .frame(maxWidth: .infinity, minHeight: minimumTapTarget)
    }

    private var loadMoreButton: some View {
        Button {
            scheduleService.loadMoreGroupSearchResults()
        } label: {
            Text("Показать ещё")
                .font(.footnote.weight(.medium))
                // Растягиваем саму метку: иначе область нажатия — по размеру текста,
                // а это меньше минимума из HIG.
                .frame(maxWidth: .infinity, minHeight: minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.accentColor)
        .accessibilityHint("Загружает следующую страницу результатов поиска")
    }
}
