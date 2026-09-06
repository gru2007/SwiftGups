import SwiftUI

/// Выбор группы поиском по всему справочнику.
///
/// Институт выбирать не нужно: справочник объединяет группы вуза (новый API)
/// и техникумов ассоциации (старый), поэтому найти можно любую группу сразу.
/// Институт остался необязательным фильтром — для тех, кто листает список,
/// а не ищет конкретную группу.
struct GroupPicker: View {
    @ObservedObject var scheduleService: ScheduleService
    let selectedGroupId: String?
    var onSelect: (Group) -> Void

    /// Сколько строк показываем за раз: справочник — тысячи групп,
    /// а листать их руками всё равно никто не станет.
    private let visibleLimit = 40
    /// HIG: минимальная область нажатия — 44×44 pt.
    private let minimumRowHeight: CGFloat = 44

    @State private var searchText = ""
    @State private var facultyFilterId: String?

    private var results: [Group] {
        scheduleService.filteredGroups(matching: searchText, facultyId: facultyFilterId)
    }

    private var facultyFilterTitle: String {
        guard let facultyFilterId,
              let faculty = scheduleService.faculties.first(where: { $0.id == facultyFilterId })
        else { return "Все институты" }
        return faculty.name
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            searchField

            if scheduleService.facultiesWithGroups.count > 1 {
                facultyFilterMenu
            }

            content
        }
        .task {
            await scheduleService.ensureGroupDirectoryLoaded()
        }
    }

    // MARK: - Шапка

    private var header: some View {
        HStack {
            Label("Группа", systemImage: "person.3.fill")
                .font(.headline)
                .foregroundStyle(.primary)

            Spacer()

            if !scheduleService.allGroups.isEmpty {
                Text("\(scheduleService.allGroups.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Всего групп: \(scheduleService.allGroups.count)")
            }
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Название группы или специальность", text: $searchText)
                // Поиск регистронезависимый, поэтому не навязываем регистр.
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Очистить поиск")
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: minimumRowHeight)
        .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
    }

    private var facultyFilterMenu: some View {
        Menu {
            // Picker внутри Menu — системный способ: галочку у выбранного
            // пункта расставляет сам SwiftUI.
            Picker("Институт", selection: $facultyFilterId) {
                Text("Все институты").tag(String?.none)

                ForEach(scheduleService.facultiesWithGroups) { faculty in
                    Text(faculty.name).tag(String?.some(faculty.id))
                }
            }
        } label: {
            HStack {
                Image(systemName: "line.3.horizontal.decrease.circle")
                Text(facultyFilterTitle)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
            }
            .font(.subheadline)
            .foregroundStyle(facultyFilterId == nil ? Color.secondary : Color.accentColor)
            .padding(.horizontal, 12)
            .frame(minHeight: minimumRowHeight)
            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 12))
        }
        .accessibilityLabel("Фильтр по институту")
    }

    // MARK: - Содержимое

    @ViewBuilder
    private var content: some View {
        if scheduleService.isLoadingDirectory && scheduleService.allGroups.isEmpty {
            statusBlock {
                ProgressView("Загружаем список групп…")
                    .foregroundStyle(.secondary)
            }
        } else if let error = scheduleService.directoryError, scheduleService.allGroups.isEmpty {
            statusBlock {
                VStack(spacing: 12) {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Повторить") {
                        Task { await scheduleService.loadGroupDirectory() }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } else if results.isEmpty {
            statusBlock {
                Text(searchText.isEmpty ? "Список групп пуст" : "Ничего не найдено")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        } else {
            resultList
        }
    }

    private var resultList: some View {
        let shown = Array(results.prefix(visibleLimit))

        return VStack(spacing: 8) {
            ForEach(shown) { group in
                groupRow(group)
            }

            if results.count > shown.count {
                Text("Показаны первые \(shown.count) из \(results.count). Уточните поиск.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 4)
            }
        }
    }

    private func groupRow(_ group: Group) -> some View {
        let isSelected = selectedGroupId == group.id

        return Button {
            onSelect(group)
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isSelected ? Color.white : Color.primary)

                    if !group.fullName.isEmpty {
                        Text(group.fullName)
                            .font(.caption)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                    }

                    if let faculty = scheduleService.facultyName(for: group) {
                        Text(faculty)
                            .font(.caption2)
                            .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.white)
                }
            }
            .padding(12)
            .frame(minHeight: minimumRowHeight)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor : Color(.systemGray6))
            )
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }

    private func statusBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity)
            .padding(.vertical, 24)
    }
}
