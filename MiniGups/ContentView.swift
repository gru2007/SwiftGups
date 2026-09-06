//
//  ContentView.swift
//  MiniGups (App Clip)
//
//  App Clip расписания: выбор факультета → группы → просмотр расписания.
//

import Foundation
import Combine
import StoreKit
import SwiftUI
import UIKit

// MARK: - Root

struct ContentView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @StateObject private var scheduleService = MiniScheduleService()
    @State private var searchText = ""
    @State private var showDatePicker = false
    @AppStorage("mini.scheduleViewMode") private var scheduleViewMode: MiniScheduleViewMode = .day
    @State private var showAppStoreOverlay = false
    @AppStorage("mini.dismissedFullAppPromoBanner") private var dismissedFullAppPromoBanner = false
    @AppStorage("mini.successfulScheduleLoads") private var successfulScheduleLoads = 0

    private var shouldShowFullAppPromo: Bool {
        !dismissedFullAppPromoBanner && successfulScheduleLoads > 0
    }

    /// Максимальная ширина контента на iPad для удобного чтения.
    private static let iPadContentMaxWidth: CGFloat = 620

    var body: some View {
        NavigationView {
            ZStack {
                LinearGradient(
                    colors: [
                        Color.blue.opacity(0.10),
                        Color.purple.opacity(0.10),
                        Color(.systemBackground)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 18) {
                        MiniHeaderCard()

                        MiniDateSelectionCard(
                            scheduleService: scheduleService,
                            showDatePicker: $showDatePicker,
                            viewMode: $scheduleViewMode
                        )

                        MiniGroupSelectionCard(
                            scheduleService: scheduleService,
                            searchText: $searchText
                        )

                        MiniScheduleDisplayCard(
                            scheduleService: scheduleService,
                            viewMode: scheduleViewMode
                        )

                        if shouldShowFullAppPromo {
                            MiniFullAppPromoBanner(
                                onInstallTap: {
                                    showAppStoreOverlay = true
                                },
                                onDismiss: {
                                    dismissedFullAppPromoBanner = true
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .frame(maxWidth: horizontalSizeClass == .regular ? Self.iPadContentMaxWidth : nil)
                    .frame(maxWidth: .infinity)
                }
            }
            .navigationTitle("MiniGups")
            .navigationBarTitleDisplayMode(.inline)
        }
        .navigationViewStyle(.stack)
        .sheet(isPresented: $showDatePicker) {
            MiniDatePickerSheet(selectedDate: $scheduleService.selectedDate) {
                scheduleService.selectDate(scheduleService.selectedDate)
            }
        }
        .appStoreOverlay(isPresented: $showAppStoreOverlay) {
            SKOverlay.AppConfiguration(appIdentifier: FullAppPromo.appStoreId, position: .bottom)
        }
        .task {
            await scheduleService.ensureGroupDirectoryLoaded()
        }
        .onChange(of: scheduleService.currentSchedule?.id) { _ in
            // "Опробовали базу": пользователь хотя бы раз успешно загрузил расписание.
            guard scheduleService.currentSchedule != nil else { return }
            successfulScheduleLoads = max(successfulScheduleLoads, 0) + 1
        }
    }
}

// MARK: - UI (design in style of main app)

private enum FullAppPromo {
    static let appStoreId: String = "6751450752" // https://apps.apple.com/us/app/swiftgups/id6751450752
}

enum MiniScheduleViewMode: String, CaseIterable, Identifiable {
    case day = "day"
    case week = "week"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .day: return "День"
        case .week: return "Неделя"
        }
    }
}

private struct MiniHeaderCard: View {
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.blue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: .blue.opacity(0.25), radius: 14, x: 0, y: 8)

                Text("🎓")
                    .font(.system(size: 34))
            }

            VStack(spacing: 4) {
                Text("Расписание ДВГУПС")
                    .font(.headline)
                    .fontWeight(.semibold)

                Text("Быстрый App Clip: выберите факультет и группу")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.08), radius: 10, x: 0, y: 6)
        )
    }
}

private struct MiniFullAppPromoBanner: View {
    let onInstallTap: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundColor(.blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Понравилось расписание?")
                        .font(.headline)
                        .fontWeight(.semibold)

                    Text("В полной версии: профиль, виджеты, Live Activity и многое другое.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Скрыть предложение"))
            }

            HStack(spacing: 12) {
                Button {
                    onInstallTap()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.down")
                        Text("Скачать полную версию")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue)
                    )
                    .foregroundColor(.white)
                }

                Button {
                    onDismiss()
                } label: {
                    Text("Позже")
                        .frame(width: 80, height: 44)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(.systemGray6))
                        )
                }
                .buttonStyle(.plain)
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

private struct MiniDateSelectionCard: View {
    @ObservedObject var scheduleService: MiniScheduleService
    @Binding var showDatePicker: Bool
    @Binding var viewMode: MiniScheduleViewMode

    private let calendar = Calendar.current

    private func startOfWeek(for date: Date) -> Date {
        let weekday = calendar.component(.weekday, from: date)
        let daysFromMonday = (weekday + 5) % 7
        return calendar.date(byAdding: .day, value: -daysFromMonday, to: date) ?? date
    }

    private var weekDates: [Date] {
        let start = startOfWeek(for: scheduleService.selectedDate)
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    private static let weekdayShortFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EE"
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return f
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d"
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Label("Навигация", systemImage: "calendar")
                    .font(.headline)

                Spacer()

                Picker("", selection: $viewMode) {
                    ForEach(MiniScheduleViewMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
            }

            HStack(spacing: 12) {
                Button {
                    let h = UIImpactFeedbackGenerator(style: .light)
                    h.impactOccurred()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scheduleService.previousWeek()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.title3)
                }

                Spacer()

                VStack(spacing: 4) {
                    Text(scheduleService.currentWeekRange())
                        .font(.headline)

                    Button("Сегодня") {
                        let h = UIImpactFeedbackGenerator(style: .light)
                        h.impactOccurred()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            scheduleService.goToCurrentWeek()
                        }
                    }
                    .font(.caption)
                }

                Spacer()

                Button {
                    let h = UIImpactFeedbackGenerator(style: .light)
                    h.impactOccurred()
                    withAnimation(.easeInOut(duration: 0.25)) {
                        scheduleService.nextWeek()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.title3)
                }
            }
            .foregroundColor(.blue)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color(.systemGray4), lineWidth: 1)
            )

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(weekDates, id: \.timeIntervalSince1970) { date in
                        let isSelected = calendar.isDate(date, inSameDayAs: scheduleService.selectedDate)
                        let isToday = calendar.isDateInToday(date)

                        Button {
                            let h = UIImpactFeedbackGenerator(style: .light)
                            h.impactOccurred()
                            withAnimation(.easeInOut(duration: 0.2)) {
                                scheduleService.selectDate(date)
                            }
                        } label: {
                            VStack(spacing: 4) {
                                Text(Self.weekdayShortFormatter.string(from: date).uppercased())
                                    .font(.caption2)
                                    .fontWeight(.semibold)
                                    .foregroundColor(isSelected ? .white : .secondary)

                                Text(Self.dayNumberFormatter.string(from: date))
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundColor(isSelected ? .white : .primary)

                                Circle()
                                    .fill(isToday ? (isSelected ? Color.white.opacity(0.9) : Color.blue) : .clear)
                                    .frame(width: 5, height: 5)
                            }
                            .frame(width: 44, height: 56)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? Color.blue : Color(.systemGray6))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(isSelected ? Color.clear : Color(.systemGray4), lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(DateFormatter.displayDateFormatter.string(from: date)))
                    }
                }
                .padding(.horizontal, 2)
            }

            Button {
                showDatePicker = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "calendar.badge.plus")
                        .foregroundColor(.blue)

                    Text("Выбрать дату")
                        .foregroundColor(.primary)

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray4), lineWidth: 1)
                )
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

private struct MiniGroupSelectionCard: View {
    @ObservedObject var scheduleService: MiniScheduleService
    @Binding var searchText: String

    /// Справочник — тысячи групп, показываем первые совпадения.
    private let visibleLimit = 30
    /// HIG: минимальная область нажатия — 44×44 pt.
    private let minimumRowHeight: CGFloat = 44

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
            HStack {
                Label("Группа", systemImage: "person.3.fill")
                    .font(.headline)

                Spacer()

                if !scheduleService.allGroups.isEmpty {
                    Text("\(scheduleService.allGroups.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Всего групп: \(scheduleService.allGroups.count)")
                }
            }

            searchField

            if scheduleService.facultiesWithGroups.count > 1 {
                facultyFilterMenu
            }

            content
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
        .task {
            await scheduleService.ensureGroupDirectoryLoaded()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Название группы или специальность", text: $searchText)
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

    @ViewBuilder
    private var content: some View {
        if scheduleService.isLoadingDirectory && scheduleService.allGroups.isEmpty {
            ProgressView("Загружаем список групп…")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else if let error = scheduleService.directoryError, scheduleService.allGroups.isEmpty {
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
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
        } else if results.isEmpty {
            Text(searchText.isEmpty ? "Список групп пуст" : "Ничего не найдено")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
        } else {
            let shown = Array(results.prefix(visibleLimit))

            VStack(spacing: 8) {
                ForEach(shown) { group in
                    MiniGroupRow(
                        group: group,
                        facultyName: scheduleService.facultyName(for: group),
                        isSelected: scheduleService.selectedGroup?.id == group.id,
                        minimumHeight: minimumRowHeight
                    ) {
                        scheduleService.selectGroup(group)
                    }
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
    }
}

private struct MiniGroupRow: View {
    let group: Group
    let facultyName: String?
    let isSelected: Bool
    let minimumHeight: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
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

                    if let facultyName {
                        Text(facultyName)
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
            .frame(minHeight: minimumHeight)
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
}

private struct MiniScheduleDisplayCard: View {
    @ObservedObject var scheduleService: MiniScheduleService
    let viewMode: MiniScheduleViewMode
    @State private var showVPNHint = false
    @State private var vpnHintTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let errorMessage = scheduleService.errorMessage {
                MiniErrorBanner(message: errorMessage) {
                    scheduleService.errorMessage = nil
                }
            }

            if scheduleService.isLoadingSchedule {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        ProgressView()
                        Text("Загрузка расписания...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        if showVPNHint {
                            MiniVPNHintBanner()
                                .frame(maxWidth: 360)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 20)
            } else if let schedule = scheduleService.currentSchedule {
                MiniScheduleMainView(
                    schedule: schedule,
                    displayGroupName: scheduleService.selectedGroup?.name,
                    selectedDate: scheduleService.selectedDate,
                    viewMode: viewMode
                )
            } else if scheduleService.selectedGroup != nil {
                MiniEmptyScheduleView()
            } else {
                MiniHintCard()
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
        .onAppear {
            updateVPNHint(isLoading: scheduleService.isLoadingSchedule)
        }
        .onChange(of: scheduleService.isLoadingSchedule) { newValue in
            updateVPNHint(isLoading: newValue)
        }
    }

    private func updateVPNHint(isLoading: Bool) {
        vpnHintTask?.cancel()
        vpnHintTask = nil

        if !isLoading {
            withAnimation(.easeInOut(duration: 0.2)) {
                showVPNHint = false
            }
            return
        }

        vpnHintTask = Task {
            try? await Task.sleep(nanoseconds: 6_000_000_000)
            guard !Task.isCancelled else { return }
            guard scheduleService.isLoadingSchedule else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVPNHint = true
                }
            }
        }
    }
}

private struct MiniHintCard: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "hand.tap")
                .foregroundColor(.blue)
            Text("Выберите группу, чтобы увидеть расписание.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
        )
    }
}

private struct MiniErrorBanner: View {
    let message: String
    let dismissAction: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
            Text(message)
                .font(.subheadline)
                .foregroundColor(.red)
                .lineLimit(4)
            Spacer()
            Button("OK") { dismissAction() }
                .font(.caption)
                .foregroundColor(.blue)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.red.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.red.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

private struct MiniVPNHintBanner: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "globe")
                .foregroundColor(.orange)
            Text("Если загрузка занимает много времени, попробуйте включить VPN.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.orange.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                )
        )
    }
}

private struct MiniEmptyScheduleView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 42))
                .foregroundColor(.secondary)

            Text("Расписание не найдено")
                .font(.headline)
                .foregroundColor(.secondary)

            Text("На выбранную неделю данные отсутствуют")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
        )
    }
}

private struct MiniScheduleMainView: View {
    let schedule: Schedule
    /// Предпочтительное название группы (выбранная пользователем); если nil — используется schedule.groupName из API
    var displayGroupName: String? = nil
    let selectedDate: Date
    let viewMode: MiniScheduleViewMode

    private let calendar = Calendar.current
    @State private var selectedLesson: Lesson? = nil

    private var daysSorted: [ScheduleDay] {
        schedule.days.sorted(by: { $0.date < $1.date })
    }

    private var selectedDay: ScheduleDay? {
        daysSorted.first(where: { calendar.isDate($0.date, inSameDayAs: selectedDate) })
    }

    private func dayKey(_ date: Date) -> String {
        DateFormatter.serverDateFormatter.string(from: date)
    }

    private var groupNameToShow: String {
        displayGroupName ?? schedule.groupName
    }

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, EEEE"
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return f
    }()

    private static let updatedFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "dd.MM, HH:mm"
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(groupNameToShow)
                        .font(.headline)
                        .lineLimit(1)

                    Text(Self.shortDateFormatter.string(from: selectedDate))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Text("Обновлено: \(Self.updatedFormatter.string(from: schedule.lastUpdated))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            if schedule.days.isEmpty {
                MiniEmptyScheduleView()
            } else {
                switch viewMode {
                case .day:
                    if let day = selectedDay {
                        MiniScheduleDayDetail(day: day) { lesson in
                            selectedLesson = lesson
                        }
                    } else {
                        MiniEmptyDayView()
                    }
                case .week:
                    MiniScheduleWeekList(
                        days: daysSorted,
                        selectedDate: selectedDate,
                        selectedDayKey: dayKey(selectedDate),
                        dayKey: dayKey,
                        onLessonTap: { lesson in
                            selectedLesson = lesson
                        }
                    )
                }
            }
        }
        .sheet(item: $selectedLesson) { lesson in
            MiniLessonDetailSheet(lesson: lesson)
        }
    }
}

private struct MiniScheduleDayDetail: View {
    let day: ScheduleDay
    let onLessonTap: (Lesson) -> Void

    private static let dayHeaderFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMMM, EEEE"
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Self.dayHeaderFormatter.string(from: day.date))
                .font(.headline)
                .fontWeight(.semibold)

            if day.lessons.isEmpty {
                Text("Нет занятий")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(day.lessons) { lesson in
                        MiniTappableLessonRow(lesson: lesson) {
                            onLessonTap(lesson)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
        )
    }
}

private struct MiniScheduleWeekList: View {
    let days: [ScheduleDay]
    let selectedDate: Date
    let selectedDayKey: String
    let dayKey: (Date) -> String
    let onLessonTap: (Lesson) -> Void

    @State private var expandedKeys: Set<String> = []
    private let calendar = Calendar.current

    private static let dayRowFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM, EEE"
        f.locale = Locale(identifier: "ru_RU")
        f.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(days) { day in
                let key = dayKey(day.date)
                let isSelected = calendar.isDate(day.date, inSameDayAs: selectedDate)

                DisclosureGroup(
                    isExpanded: Binding(
                        get: { expandedKeys.contains(key) },
                        set: { newValue in
                            if newValue { expandedKeys.insert(key) } else { expandedKeys.remove(key) }
                        }
                    )
                ) {
                    if day.lessons.isEmpty {
                        Text("Нет занятий")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 8)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(day.lessons) { lesson in
                                MiniTappableLessonRow(lesson: lesson) {
                                    onLessonTap(lesson)
                                }
                            }
                        }
                        .padding(.top, 8)
                    }
                } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(day.weekday)
                                .font(.subheadline)
                                .fontWeight(.semibold)

                            Text(Self.dayRowFormatter.string(from: day.date))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Text(day.lessons.isEmpty ? "—" : "\(day.lessons.count)")
                            .font(.caption)
                            .foregroundColor(isSelected ? .white : .secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(isSelected ? Color.blue : Color(.systemGray5))
                            )
                    }
                    .padding(.vertical, 6)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(isSelected ? Color.blue.opacity(0.08) : Color(.systemGray6))
                )
            }
        }
        .onAppear {
            expandedKeys = [selectedDayKey]
        }
        .onChange(of: selectedDayKey) { newKey in
            expandedKeys = [newKey]
        }
    }
}

private struct MiniEmptyDayView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "calendar")
                .font(.system(size: 34))
                .foregroundColor(.secondary)
            Text("На этот день нет расписания")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color(.systemGray6))
        )
    }
}

private struct MiniTappableLessonRow: View {
    let lesson: Lesson
    let action: () -> Void

    var body: some View {
        Button {
            let h = UIImpactFeedbackGenerator(style: .light)
            h.prepare()
            h.impactOccurred()
            action()
        } label: {
            MiniLessonRow(lesson: lesson)
        }
        .buttonStyle(MiniLessonPressButtonStyle())
    }
}

private struct MiniLessonPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.06 : 0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.primary.opacity(configuration.isPressed ? 0.12 : 0), lineWidth: 1)
            )
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private struct MiniLessonRow: View {
    let lesson: Lesson

    private var lessonTypeColor: Color {
        switch lesson.type {
        case .lecture: return .blue
        case .practice: return .green
        case .laboratory: return .orange
        case .unknown: return .gray
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(lesson.pairNumber) пара")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(lessonTypeColor)

                Text("\(lesson.timeStart)-\(lesson.timeEnd)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .frame(width: 70, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(lesson.subject)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .lineLimit(2)

                Text(lesson.typeTitle)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(lessonTypeColor.opacity(0.18))
                    )
                    .foregroundColor(lessonTypeColor)

                if let teacher = lesson.teacher, !teacher.name.isEmpty {
                    Text(teacher.name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                if let room = lesson.room, !room.isEmpty {
                    Text("📍 \(room)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 4, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray4), lineWidth: 0.5)
                )
        )
    }
}

private struct MiniLessonDetailSheet: View {
    let lesson: Lesson
    @Environment(\.dismiss) private var dismiss

    private var lessonTypeColor: Color {
        switch lesson.type {
        case .lecture: return .blue
        case .practice: return .green
        case .laboratory: return .orange
        case .unknown: return .gray
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(lesson.subject)
                            .font(.title2)
                            .fontWeight(.bold)

                        HStack {
                            Text(lesson.typeTitle)
                                .font(.subheadline)
                                .fontWeight(.semibold)
                                .foregroundColor(lessonTypeColor)
                            Spacer()
                            Text("\(lesson.pairNumber) пара")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(lessonTypeColor.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(lessonTypeColor.opacity(0.2), lineWidth: 1)
                            )
                    )

                    MiniInfoRow(icon: "clock", title: "Время", value: "\(lesson.timeStart) - \(lesson.timeEnd)", color: .blue)

                    if let room = lesson.room, !room.isEmpty {
                        MiniInfoRow(icon: "location", title: "Аудитория", value: room, color: .green)
                    }

                    if let teacher = lesson.teacher, !teacher.name.isEmpty {
                        MiniInfoRow(icon: "person", title: "Преподаватель", value: teacher.name, color: .purple)
                    }

                    if !lesson.groups.isEmpty {
                        MiniInfoRow(icon: "person.3", title: "Группы", value: lesson.groups.joined(separator: ", "), color: .blue)
                    }
                }
                .padding(16)
            }
            .navigationTitle("Детали пары")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Text("Закрыть")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

private struct MiniInfoRow: View {
    let icon: String
    let title: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.body)
            }

            Spacer()
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color(.systemGray5), lineWidth: 0.5)
                )
        )
    }
}

private struct MiniDatePickerSheet: View {
    @Binding var selectedDate: Date
    let onDateSelected: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                Text("Выберите дату")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .padding(.top, 8)

                DatePicker(
                    "Дата",
                    selection: $selectedDate,
                    displayedComponents: [.date]
                )
                .datePickerStyle(.graphical)
                .padding(.horizontal, 10)

                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        onDateSelected()
                        dismiss()
                    } label: {
                        Text("Готово")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
    }
}

// MARK: - Faculty missing ID banner (copy of main app component)

// MARK: - Domain models (lightweight copy from main app)

struct Faculty: Codable, Identifiable, Hashable {
    let id: String
    let name: String
}

struct Group: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let fullName: String
    let facultyId: String
}

enum LessonType: String, Codable, CaseIterable {
    case lecture = "Лекции"
    case practice = "Практика"
    case laboratory = "Лабораторные работы"
    case unknown = "Неизвестно"

    init(from rawValue: String) {
        // Новый API вуза и старый API техникумов пишут тип по-разному
        // («Лекции» / «Лекция»), поэтому сравниваем по началу слова.
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "ё", with: "е")

        if normalized.hasPrefix("лекц") {
            self = .lecture
        } else if normalized.hasPrefix("практ") || normalized.hasPrefix("семинар") {
            self = .practice
        } else if normalized.hasPrefix("лаб") {
            self = .laboratory
        } else {
            self = .unknown
        }
    }
}

struct Teacher: Codable, Hashable {
    let name: String
    let email: String?

    init(name: String, email: String? = nil) {
        self.name = name
        self.email = email
    }
}

struct Lesson: Codable, Identifiable, Hashable {
    let id: UUID
    let pairNumber: Int
    let timeStart: String
    let timeEnd: String
    let type: LessonType
    let subject: String
    let room: String?
    let teacher: Teacher?
    let groups: [String]
    let onlineLink: String?
    /// Исходное название типа занятия с сервера («Лекции», «Экзамен», ...),
    /// чтобы не показывать «Неизвестно» для типов вне `LessonType`.
    let typeName: String?

    init(
        id: UUID = UUID(),
        pairNumber: Int,
        timeStart: String,
        timeEnd: String,
        type: LessonType,
        subject: String,
        room: String? = nil,
        teacher: Teacher? = nil,
        groups: [String] = [],
        onlineLink: String? = nil,
        typeName: String? = nil
    ) {
        self.id = id
        self.pairNumber = pairNumber
        self.timeStart = timeStart
        self.timeEnd = timeEnd
        self.type = type
        self.subject = subject
        self.room = room
        self.teacher = teacher
        self.groups = groups
        self.onlineLink = onlineLink
        self.typeName = typeName
    }

    /// Название типа занятия для интерфейса: сначала то, что прислал сервер.
    var typeTitle: String {
        if let typeName = typeName?.trimmingCharacters(in: .whitespacesAndNewlines), !typeName.isEmpty {
            return typeName
        }
        return type.rawValue
    }
}

struct ScheduleDay: Codable, Identifiable, Hashable {
    let id: UUID
    let date: Date
    let weekday: String
    let lessons: [Lesson]

    init(id: UUID = UUID(), date: Date, weekday: String, lessons: [Lesson] = []) {
        self.id = id
        self.date = date
        self.weekday = weekday
        self.lessons = lessons
    }
}

struct Schedule: Codable, Identifiable, Hashable {
    let id: UUID
    let groupId: String
    let groupName: String
    let startDate: Date
    let endDate: Date
    let days: [ScheduleDay]
    let lastUpdated: Date

    init(
        id: UUID = UUID(),
        groupId: String,
        groupName: String,
        startDate: Date,
        endDate: Date,
        days: [ScheduleDay] = [],
        lastUpdated: Date = Date()
    ) {
        self.id = id
        self.groupId = groupId
        self.groupName = groupName
        self.startDate = startDate
        self.endDate = endDate
        self.days = days
        self.lastUpdated = lastUpdated
    }
}

struct LessonTime: Identifiable, Codable {
    let id = UUID()
    let number: Int
    let startTime: String
    let endTime: String

    static let schedule = [
        LessonTime(number: 1, startTime: "8:05", endTime: "9:35"),
        LessonTime(number: 2, startTime: "9:50", endTime: "11:20"),
        LessonTime(number: 3, startTime: "11:35", endTime: "13:05"),
        LessonTime(number: 4, startTime: "13:35", endTime: "15:05"),
        LessonTime(number: 5, startTime: "15:15", endTime: "16:45"),
        LessonTime(number: 6, startTime: "16:55", endTime: "18:25")
    ]
}

// MARK: - Schedule service (adapted from SwiftGups/ScheduleService.swift)

@MainActor
final class MiniScheduleService: ObservableObject {
    @Published var faculties: [Faculty] = []
    @Published var selectedFaculty: Faculty?
    @Published var selectedGroup: Group?
    @Published var currentSchedule: Schedule?
    @Published var selectedDate: Date = Date()

    /// Единый справочник групп — по нему идёт выбор, без выбора института.
    @Published var allGroups: [Group] = []
    @Published var isLoadingDirectory = false
    @Published var directoryError: String?

    @Published var isLoadingFaculties = false
    @Published var isLoadingSchedule = false

    @Published var errorMessage: String?

    private let apiClient: DVGUPSAPIClient
    private var didLoadFaculties = false

    private let defaults = UserDefaults.standard
    private let kFacultyId = "mini.facultyId"
    private let kGroupId = "mini.groupId"
    private let kGroupName = "mini.groupName"

    init() {
        self.apiClient = DVGUPSAPIClient()
    }

    func ensureFacultiesLoaded() async {
        guard !didLoadFaculties else { return }
        await loadFaculties()
    }

    func loadFaculties() async {
        isLoadingFaculties = true
        errorMessage = nil

        do {
            let result = try await apiClient.fetchFaculties()
            faculties = result.faculties
            didLoadFaculties = true

            // Институт следует за выбранной группой, а не наоборот:
            // умолчания больше нет, только обновление ссылки на объект.
            if let selectedFaculty {
                self.selectedFaculty = faculties.first(where: { $0.id == selectedFaculty.id }) ?? selectedFaculty
            }

        } catch {
            didLoadFaculties = true
            errorMessage = error.localizedDescription
        }

        isLoadingFaculties = false
    }

    func selectGroup(_ group: Group) {
        selectedGroup = group
        selectedFaculty = faculties.first { $0.id == group.facultyId }
        currentSchedule = nil
        errorMessage = nil
        isLoadingSchedule = true
        defaults.set(group.id, forKey: kGroupId)
        defaults.set(group.name, forKey: kGroupName)
        defaults.set(group.facultyId, forKey: kFacultyId)

        Task { await loadWeekSchedule() }
    }

    // MARK: - Единый справочник групп

    func ensureGroupDirectoryLoaded() async {
        guard allGroups.isEmpty, !isLoadingDirectory else { return }
        await loadGroupDirectory()
    }

    /// Грузит справочник целиком, чтобы поиск потом шёл локально и мгновенно.
    func loadGroupDirectory() async {
        isLoadingDirectory = true
        directoryError = nil
        defer { isLoadingDirectory = false }

        await ensureFacultiesLoaded()

        let directory = await apiClient.fetchCombinedGroupDirectory(faculties: faculties)

        guard !directory.isEmpty else {
            directoryError = "Не удалось загрузить список групп. Проверьте соединение и повторите."
            return
        }

        allGroups = directory

        // Восстанавливаем ранее выбранную группу.
        if selectedGroup == nil, let storedGroupId = defaults.string(forKey: kGroupId) {
            let storedName = defaults.string(forKey: kGroupName) ?? ""
            if let restored = allGroups.first(where: { $0.id == storedGroupId })
                ?? allGroups.first(where: { $0.name.caseInsensitiveCompare(storedName) == .orderedSame }) {
                selectedGroup = restored
                selectedFaculty = faculties.first { $0.id == restored.facultyId }
                await loadWeekSchedule()
            }
        }
    }

    /// Поиск по справочнику с необязательным фильтром по институту.
    ///
    /// Совпадение по началу названия поднимается наверх: набирая «БОД21»,
    /// человек ищет группу, а не специальность с такой подстрокой.
    func filteredGroups(matching searchText: String, facultyId: String? = nil) -> [Group] {
        var result = allGroups

        if let facultyId, !facultyId.isEmpty {
            result = result.filter { $0.facultyId == facultyId }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return result }

        return result
            .filter { group in
                group.name.localizedCaseInsensitiveContains(query) ||
                group.fullName.localizedCaseInsensitiveContains(query)
            }
            .sorted { lhs, rhs in
                let lhsPrefix = lhs.name.lowercased().hasPrefix(query.lowercased())
                let rhsPrefix = rhs.name.lowercased().hasPrefix(query.lowercased())
                if lhsPrefix != rhsPrefix { return lhsPrefix }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
    }

    /// Институты, у которых в справочнике есть хотя бы одна группа.
    var facultiesWithGroups: [Faculty] {
        let ids = Set(allGroups.map { $0.facultyId })
        return faculties.filter { ids.contains($0.id) }
    }

    func facultyName(for group: Group) -> String? {
        guard !group.facultyId.isEmpty else { return nil }
        return faculties.first { $0.id == group.facultyId }?.name
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        Task { [selectedGroup] in
            if selectedGroup != nil {
                await MainActor.run { self.isLoadingSchedule = true }
                await loadWeekSchedule()
            }
        }
    }

    func loadWeekSchedule() async {
        guard let group = selectedGroup else {
            errorMessage = "Группа не выбрана"
            return
        }

        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: selectedDate)
        let daysFromMonday = (weekday + 5) % 7

        guard let startOfWeek = calendar.date(byAdding: .day, value: -daysFromMonday, to: selectedDate),
              let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) else {
            errorMessage = "Ошибка вычисления недели"
            return
        }

        isLoadingSchedule = true
        errorMessage = nil

        do {
            let schedule = try await apiClient.fetchSchedule(for: group.id, startDate: startOfWeek, endDate: endOfWeek)
            currentSchedule = schedule
        } catch {
            currentSchedule = nil
            errorMessage = error.localizedDescription
        }

        isLoadingSchedule = false
    }

    func previousWeek() {
        guard let newDate = Calendar.current.date(byAdding: .weekOfYear, value: -1, to: selectedDate) else { return }
        selectDate(newDate)
    }

    func nextWeek() {
        guard let newDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: selectedDate) else { return }
        selectDate(newDate)
    }

    func goToCurrentWeek() {
        selectDate(Date())
    }

    func currentWeekRange() -> String {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: selectedDate)
        let daysFromMonday = (weekday + 5) % 7

        guard let startOfWeek = calendar.date(byAdding: .day, value: -daysFromMonday, to: selectedDate),
              let endOfWeek = calendar.date(byAdding: .day, value: 6, to: startOfWeek) else {
            return "Неизвестная неделя"
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Asia/Vladivostok")

        return "\(formatter.string(from: startOfWeek)) - \(formatter.string(from: endOfWeek))"
    }
}

// MARK: - API client (based on SwiftGups/APIClient.swift, schedule only)

enum APIError: Error, LocalizedError {
    case invalidURL
    case parseError(String)
    case networkError(Error)
    case invalidResponse
    case vpnOrBlockedNetwork
    case requestTimedOut(seconds: Int)
    case emptyResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Неверный URL"
        case .parseError(let message):
            return "Ошибка парсинга: \(message)"
        case .networkError(let error):
            return "Ошибка сети: \(error.localizedDescription)"
        case .invalidResponse:
            return "Неверный формат ответа сервера"
        case .vpnOrBlockedNetwork:
            return "Не удалось подключиться к серверу. Возможно включен VPN или сеть блокирует доступ к dvgups.ru. Отключите VPN и повторите попытку."
        case .requestTimedOut(let seconds):
            return "Сервер не ответил за \(seconds) сек. Проверьте интернет и повторите."
        case .emptyResponse:
            return "Сервер вернул пустой ответ. Повторите попытку."
        }
    }
}

@MainActor
final class DVGUPSAPIClient: ObservableObject {
    private let primaryBaseURL = URL(string: "https://dvgups.ru")!
    /// Фолбек отключён: App Clip использует только `dvgups.ru`.
    private let fallbackBaseURL = URL(string: "https://dvgups.ru")!

    private let session: URLSession
    private let requestTimeoutSeconds: TimeInterval = 8
    /// Справочник групп нового API — выгружается постранично, поэтому кэшируем на время сессии.
    private var cachedGroupDirectory: [Group]?

    init(session: URLSession = .shared) {
        self.session = session
    }

    struct FacultiesResult {
        let faculties: [Faculty]
        let missingIdNames: [String]
    }

    func fetchFaculties() async throws -> FacultiesResult {
        let response: APIEnvelope<[[String?]]> = try await request(
            baseURL: primaryBaseURL,
            path: "/api/v1/timetable/faculties",
            queryItems: []
        )

        var faculties: [Faculty] = []
        var missingIdNames: [String] = []
        for row in response.data {
            let rawId = row.count > 0 ? row[0] : nil
            let name = row.count > 1 ? row[1] : nil

            guard let facultyName = name?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !facultyName.isEmpty else { continue }

            guard let id = rawId?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !id.isEmpty else {
                missingIdNames.append(facultyName)
                continue
            }

            faculties.append(Faculty(id: id, name: facultyName))
        }

        let unique = Dictionary(grouping: faculties, by: { $0.id })
            .compactMap { $0.value.first }
            .sorted { $0.name < $1.name }

        return FacultiesResult(
            faculties: unique,
            missingIdNames: Array(Set(missingIdNames)).sorted()
        )
    }

    /// Список групп факультета/института.
    ///
    /// Группы вуза переехали в новый справочник `/groups/options`, техникумы
    /// ассоциации остались на старом `/groups/by-faculty`: сначала новый путь,
    /// при пустом результате — старый.
    func fetchGroups(for facultyId: String) async throws -> [Group] {
        if let directory = try? await fetchGroupDirectory() {
            let matching = directory.filter { $0.facultyId == facultyId }
            if !matching.isEmpty { return matching }
        }

        return try await fetchLegacyGroups(for: facultyId)
    }

    /// Полный справочник групп нового API (все страницы `/groups/options`).
    ///
    /// Фильтровать по институту эндпоинт не умеет, поэтому выгружаем целиком
    /// и держим в памяти — смена института не должна тянуть его заново.
    func fetchGroupDirectory() async throws -> [Group] {
        if let cached = cachedGroupDirectory, !cached.isEmpty { return cached }

        struct PageDTO: Decodable {
            let items: [GroupOptionDTO]?
            let hasMore: Bool?

            enum CodingKeys: String, CodingKey {
                case items
                case hasMore = "has_more"
            }
        }

        struct GroupOptionDTO: Decodable {
            let id: String?
            let name: String?
            let field: String?
            let facultyId: String?

            enum CodingKeys: String, CodingKey {
                case id, name, field
                case facultyId = "faculty_id"
            }
        }

        let pageSize = 200
        var collected: [Group] = []
        var seenIds = Set<String>()
        var page = 1

        while page <= 60 {
            let response: APIEnvelope<PageDTO> = try await request(
                baseURL: primaryBaseURL,
                path: "/api/v1/timetable/groups/options",
                queryItems: [
                    URLQueryItem(name: "page", value: String(page)),
                    URLQueryItem(name: "limit", value: String(pageSize))
                ]
            )

            let items = response.data.items ?? []
            for dto in items {
                let id = (dto.id ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let name = (dto.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !id.isEmpty, !name.isEmpty, seenIds.insert(id).inserted else { continue }

                collected.append(
                    Group(
                        id: id,
                        name: name,
                        fullName: (dto.field ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                        facultyId: (dto.facultyId ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                )
            }

            guard response.data.hasMore == true, !items.isEmpty else { break }
            page += 1
        }

        let directory = collected.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        cachedGroupDirectory = directory
        return directory
    }

    /// Единый справочник групп: вуз (новый API) плюс техникумы (старый).
    ///
    /// Объединить их может только клиент, а без объединения половина групп
    /// просто не находится поиском. Метод не бросает: частичный справочник
    /// полезнее пустого.
    func fetchCombinedGroupDirectory(faculties: [Faculty]) async -> [Group] {
        var collected: [Group] = []
        var seenIds = Set<String>()

        func append(_ groups: [Group]) {
            for group in groups where seenIds.insert(group.id).inserted {
                collected.append(group)
            }
        }

        let directory = (try? await fetchGroupDirectory()) ?? []
        append(directory)

        let covered = Set(directory.map { $0.facultyId }.filter { !$0.isEmpty })
        let legacyFaculties = faculties.filter { !covered.contains($0.id) }

        if !legacyFaculties.isEmpty {
            let legacy = await withTaskGroup(of: [Group].self) { group in
                for faculty in legacyFaculties {
                    group.addTask { [weak self] in
                        guard let self else { return [] }
                        return (try? await self.fetchLegacyGroups(for: faculty.id)) ?? []
                    }
                }

                var result: [Group] = []
                for await groups in group {
                    result.append(contentsOf: groups)
                }
                return result
            }

            append(legacy)
        }

        return collected.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    /// Старый эндпоинт групп по факультету (техникумы ассоциации).
    private func fetchLegacyGroups(for facultyId: String) async throws -> [Group] {
        struct GroupDTO: Decodable {
            let id: String
            let name: String
            let field: String
        }

        let response: APIEnvelope<[GroupDTO]> = try await request(
            baseURL: primaryBaseURL,
            path: "/api/v1/timetable/groups/by-faculty",
            queryItems: [URLQueryItem(name: "facultyId", value: facultyId)]
        )

        return response.data
            .map { Group(id: $0.id, name: $0.name, fullName: $0.field, facultyId: facultyId) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    func fetchSchedule(for groupId: String, startDate: Date = Date(), endDate: Date? = nil) async throws -> Schedule {
        let daysCount = Self.computeDaysCount(startDate: startDate, endDate: endDate)
        let startDateString = DateFormatter.serverDateFormatter.string(from: startDate)

        // Новый формат добавил `begins_at`/`ends_at`, `day_layout_id`, `calendar_id`
        // и расширенные сведения о группах. Старый формат присылает тот же каркас
        // без этих полей — поэтому обязательных полей здесь нет вовсе.
        struct ScheduleItemDTO: Decodable {
            let startTime: String?
            let endTime: String?
            let date: String?
            let lessonData: LessonDataDTO?

            struct LessonDataDTO: Decodable {
                let courseType: NamedDTO?
                let courseSubject: NamedDTO?
                let teacherList: [TeacherDTO]?
                let studentList: [StudentDTO]?
                let studyPlace: StudyPlaceDTO?
                let beginsAt: String?
                let endsAt: String?

                struct NamedDTO: Decodable {
                    let name: String?
                    let nameAbbr: String?
                    enum CodingKeys: String, CodingKey { case name; case nameAbbr = "name_abbr" }
                }
                struct TeacherDTO: Decodable {
                    let name: String?
                    let nameAbbr: String?
                    enum CodingKeys: String, CodingKey { case name; case nameAbbr = "name_abbr" }

                    var displayName: String? {
                        for candidate in [nameAbbr, name] {
                            let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let value, !value.isEmpty { return value }
                        }
                        return nil
                    }
                }
                struct StudentDTO: Decodable {
                    let name: String?
                    let nameAbbr: String?
                    let studentGroupName: String?

                    enum CodingKeys: String, CodingKey {
                        case name
                        case nameAbbr = "name_abbr"
                        case studentGroupName = "student_group_name"
                    }

                    var groupName: String? {
                        for candidate in [studentGroupName, nameAbbr, name] {
                            let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines)
                            if let value, !value.isEmpty { return value }
                        }
                        return nil
                    }
                }
                struct StudyPlaceDTO: Decodable {
                    let name: String?
                    let ownerName: String?
                    enum CodingKeys: String, CodingKey { case name; case ownerName = "owner_name" }
                }

                enum CodingKeys: String, CodingKey {
                    case courseType = "course_type"
                    case courseSubject = "course_subject"
                    case teacherList = "teacher_list"
                    case studentList = "student_list"
                    case studyPlace = "study_place"
                    case beginsAt = "begins_at"
                    case endsAt = "ends_at"
                }
            }

            enum CodingKeys: String, CodingKey {
                case startTime = "start_time"
                case endTime = "end_time"
                case date
                case lessonData = "lesson_data"
            }

            /// Дата пары: `date`, иначе — дата из `begins_at`.
            var lessonDate: Date? {
                if let date, let parsed = DateFormatter.serverDateFormatter.date(from: date) {
                    return parsed
                }
                if let beginsAt = lessonData?.beginsAt,
                   let dayPart = beginsAt.split(separator: "T").first {
                    return DateFormatter.serverDateFormatter.date(from: String(dayPart))
                }
                return nil
            }

            var startHHmm: String? {
                ScheduleTimeFormat.hhmm(from: startTime ?? Self.timePart(of: lessonData?.beginsAt), roundingUp: false)
            }

            /// Новый API отдаёт конец пары как «13:04:59» — округляем до «13:05».
            var endHHmm: String? {
                ScheduleTimeFormat.hhmm(from: endTime ?? Self.timePart(of: lessonData?.endsAt), roundingUp: true)
            }

            private static func timePart(of timestamp: String?) -> String? {
                guard let timestamp, let time = timestamp.split(separator: "T").last else { return nil }
                return String(time)
            }
        }

        let response: APIEnvelope<[ScheduleItemDTO]> = try await request(
            baseURL: primaryBaseURL,
            path: "/api/v1/timetable/schedule",
            queryItems: [
                URLQueryItem(name: "scheduleType", value: "gr"),
                URLQueryItem(name: "parameter", value: groupId),
                URLQueryItem(name: "days", value: String(daysCount)),
                URLQueryItem(name: "startDate", value: startDateString)
            ]
        )

        var lessonsByDate: [Date: [Lesson]] = [:]
        var groupNameHits: [String: Int] = [:]

        for item in response.data {
            guard let lessonDate = item.lessonDate,
                  let timeStartHHmm = item.startHHmm else {
                continue
            }

            let lessonData = item.lessonData
            let timeEndHHmm = item.endHHmm ?? timeStartHHmm

            // У потоковых пар в `student_list` перечислены сразу несколько групп,
            // поэтому имя группы выбираем по частоте.
            let groups = (lessonData?.studentList ?? []).compactMap { $0.groupName }
            for name in groups {
                groupNameHits[name, default: 0] += 1
            }

            let typeName = lessonData?.courseType?.name
            let teacherName = (lessonData?.teacherList ?? []).compactMap { $0.displayName }.first

            let lesson = Lesson(
                // Точный номер пары проставим ниже, когда увидим весь день целиком.
                pairNumber: ScheduleTimeFormat.bellPairNumber(forStartTime: timeStartHHmm) ?? 0,
                timeStart: timeStartHHmm,
                timeEnd: timeEndHHmm,
                type: LessonType(from: typeName ?? ""),
                subject: lessonData?.courseSubject?.name ?? typeName ?? "Занятие",
                room: Self.composeRoom(
                    name: lessonData?.studyPlace?.name,
                    ownerName: lessonData?.studyPlace?.ownerName
                ),
                teacher: teacherName.map { Teacher(name: $0) },
                groups: groups,
                onlineLink: nil,
                typeName: typeName
            )

            lessonsByDate[lessonDate, default: []].append(lesson)
        }

        let resolvedGroupName = groupNameHits.max(by: { $0.value < $1.value })?.key

        let days: [ScheduleDay] = lessonsByDate
            .map { (date, lessons) in
                let weekday = DateFormatter.weekdayRuFormatter.string(from: date).capitalized
                return ScheduleDay(
                    date: date,
                    weekday: weekday,
                    lessons: ScheduleTimeFormat.numberPairs(in: lessons)
                )
            }
            .sorted { $0.date < $1.date }

        let end = endDate ?? Calendar.current.date(byAdding: .day, value: max(0, daysCount - 1), to: startDate) ?? startDate

        return Schedule(
            groupId: groupId,
            groupName: resolvedGroupName ?? "Группа \(groupId)",
            startDate: startDate,
            endDate: end,
            days: days
        )
    }

    private struct APIEnvelope<T: Decodable>: Decodable {
        let status: String?
        let data: T
    }

    private func request<T: Decodable>(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> T {
        do {
            return try await performRequest(baseURL: baseURL, path: path, queryItems: queryItems)
        } catch {
            guard shouldFallback(from: error),
                  fallbackBaseURL.host != baseURL.host else { throw error }
            return try await performRequest(baseURL: fallbackBaseURL, path: path, queryItems: queryItems)
        }
    }

    private func performRequest<T: Decodable>(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> T {
        let cleanPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let endpointURL = baseURL.appendingPathComponent(cleanPath)
        guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else { throw APIError.invalidURL }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = requestTimeoutSeconds

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

            if (500...599).contains(http.statusCode), baseURL == primaryBaseURL {
                throw APIError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                throw APIError.invalidResponse
            }
            
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
               text == "{}" || text.isEmpty {
                throw APIError.emptyResponse
            }

            do {
                return try JSONDecoder().decode(T.self, from: data)
            } catch {
                let preview = String(data: data, encoding: .utf8) ?? ""
                throw APIError.parseError("\(error.localizedDescription). Response preview: \(preview.prefix(300))")
            }
        } catch {
            if let urlError = error as? URLError {
                switch urlError.code {
                case .timedOut:
                    throw APIError.requestTimedOut(seconds: Int(requestTimeoutSeconds))
                case .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
                    throw APIError.vpnOrBlockedNetwork
                default:
                    break
                }
            }
            throw APIError.networkError(error)
        }
    }

    private func shouldFallback(from error: Error) -> Bool {
        if let apiError = error as? APIError {
            switch apiError {
            case .vpnOrBlockedNetwork, .invalidResponse, .requestTimedOut, .emptyResponse:
                return true
            default:
                return false
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut, .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed:
                return true
            default:
                return false
            }
        }
        return false
    }

    private static func computeDaysCount(startDate: Date, endDate: Date?) -> Int {
        guard let endDate else { return 7 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        let components = calendar.dateComponents([.day], from: start, to: end)
        let diff = (components.day ?? 0)
        return max(1, diff + 1)
    }

    private static func composeRoom(name: String?, ownerName: String?) -> String? {
        // Новый API присылает аудиторию с двойными пробелами ("а.  418") — схлопываем.
        func collapse(_ value: String?) -> String {
            (value ?? "").split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }

        let trimmedName = collapse(name)
        guard !trimmedName.isEmpty else { return nil }

        let owner = collapse(ownerName)
        return owner.isEmpty ? trimmedName : "\(trimmedName) • \(owner)"
    }
}

// MARK: - Время пар
//
// Namespace вне `DVGUPSAPIClient`: клиент изолирован на `@MainActor`, а этими
// помощниками пользуются в том числе разборщики DTO вне главного актора.

enum ScheduleTimeFormat {
    /// "11:35:00" → "11:35"; "13:04:59" при `roundingUp` → "13:05".
    static func hhmm(from raw: String?, roundingUp: Bool) -> String? {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }

        let parts = raw.split(separator: ":")
        guard parts.count >= 2, var hour = Int(parts[0]), var minute = Int(parts[1]) else {
            return raw
        }

        let seconds = parts.count >= 3 ? (Int(parts[2]) ?? 0) : 0
        if roundingUp, seconds >= 30 {
            minute += 1
            if minute >= 60 {
                minute -= 60
                hour = (hour + 1) % 24
            }
        }

        return String(format: "%02d:%02d", hour, minute)
    }

    static func minutesSinceMidnight(_ hhmm: String) -> Int {
        let parts = hhmm.split(separator: ":")
        guard parts.count >= 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return 0 }
        return hour * 60 + minute
    }

    /// Номер пары по сетке звонков. `nil` — время не из сетки (своя сетка у техникумов).
    static func bellPairNumber(forStartTime hhmm: String) -> Int? {
        let target = minutesSinceMidnight(hhmm)
        for bell in LessonTime.schedule where minutesSinceMidnight(bell.startTime) == target {
            return bell.number
        }
        return nil
    }

    /// Сортирует пары дня по времени и проставляет номера.
    ///
    /// Пары вне сетки звонков нумеруем по порядку внутри дня — иначе они
    /// получают номер 0 и слипаются при сортировке.
    static func numberPairs(in lessons: [Lesson]) -> [Lesson] {
        let sorted = lessons.sorted { lhs, rhs in
            let lhsMinutes = minutesSinceMidnight(lhs.timeStart)
            let rhsMinutes = minutesSinceMidnight(rhs.timeStart)
            if lhsMinutes != rhsMinutes { return lhsMinutes < rhsMinutes }
            return lhs.subject.localizedCompare(rhs.subject) == .orderedAscending
        }

        // Пары в одно и то же время (подгруппы) должны получить один номер.
        var numbers: [Int: Int] = [:] // минуты начала -> номер пары
        var nextOrdinal = 0

        return sorted.map { lesson in
            let minutes = minutesSinceMidnight(lesson.timeStart)

            let number: Int
            if let known = numbers[minutes] {
                number = known
            } else {
                nextOrdinal += 1
                number = lesson.pairNumber > 0 ? lesson.pairNumber : nextOrdinal
                numbers[minutes] = number
            }
            nextOrdinal = max(nextOrdinal, number)

            guard number != lesson.pairNumber else { return lesson }

            return Lesson(
                id: lesson.id,
                pairNumber: number,
                timeStart: lesson.timeStart,
                timeEnd: lesson.timeEnd,
                type: lesson.type,
                subject: lesson.subject,
                room: lesson.room,
                teacher: lesson.teacher,
                groups: lesson.groups,
                onlineLink: lesson.onlineLink,
                typeName: lesson.typeName
            )
        }
    }
}

// MARK: - DateFormatter helpers (subset from main app)

extension DateFormatter {
    static let displayDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd MMM yyyy, EEEE"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return formatter
    }()

    static let serverDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return formatter
    }()

    static let weekdayRuFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE"
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: "Asia/Vladivostok")
        return formatter
    }()
}

// MARK: - Preview

#Preview {
    ContentView()
}
