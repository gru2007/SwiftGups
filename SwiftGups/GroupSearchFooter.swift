import SwiftUI

/// Подвал списка групп: состояние серверного поиска по всему вузу.
///
/// Новый API умеет искать группу по всему справочнику (`/groups/options?q=`),
/// поэтому в списке появляются группы других институтов — об этом и говорит подвал.
struct GroupSearchFooter: View {
    @ObservedObject var scheduleService: ScheduleService
    let searchText: String

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        if query.count >= 2 {
            VStack(spacing: 8) {
                if scheduleService.isSearchingGroups {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Ищем группу по всему вузу...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } else if scheduleService.groupSearchHasMore {
                    Button("Показать ещё группы") {
                        scheduleService.loadMoreGroupSearchResults()
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 4)
        }
    }
}
