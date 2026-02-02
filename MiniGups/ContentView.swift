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

                        MiniFacultySelectionCard(scheduleService: scheduleService)

                        MiniDateSelectionCard(
                            scheduleService: scheduleService,
                            showDatePicker: $showDatePicker,
                            viewMode: $scheduleViewMode
                        )

                        if scheduleService.selectedFaculty != nil {
                            MiniGroupSelectionCard(
                                scheduleService: scheduleService,
                                searchText: $searchText
                            )
                        }

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
            await scheduleService.ensureFacultiesLoaded()
            if scheduleService.selectedFaculty != nil {
                await scheduleService.loadGroups()
            }
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

private struct MiniFacultySelectionCard: View {
    @ObservedObject var scheduleService: MiniScheduleService
    @State private var showVPNHint = false
    @State private var vpnHintTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Институт/Факультет", systemImage: "building.2.fill")
                .font(.headline)

            Menu {
                if scheduleService.isLoadingFaculties {
                    Text("Загрузка институтов...")
                } else if scheduleService.faculties.isEmpty {
                    Text("Нет доступных институтов")
                } else {
                    ForEach(scheduleService.faculties) { faculty in
                        Button {
                            scheduleService.selectFaculty(faculty)
                        } label: {
                            HStack {
                                Text(faculty.name)
                                if scheduleService.selectedFaculty?.id == faculty.id {
                                    Spacer()
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(scheduleService.selectedFaculty?.name ?? (scheduleService.isLoadingFaculties ? "Загрузка..." : "Выберите институт/факультет"))
                        .foregroundColor(scheduleService.selectedFaculty != nil ? .primary : .secondary)
                        .lineLimit(2)

                    Spacer()

                    Image(systemName: "chevron.down")
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

            if showVPNHint {
                MiniVPNHintBanner()
            }

            MiniFacultyMissingIdBanner(missingNames: scheduleService.facultiesMissingIDs)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
        .onAppear {
            updateVPNHint(isLoading: scheduleService.isLoadingFaculties)
        }
        .onChange(of: scheduleService.isLoadingFaculties) { newValue in
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
            guard scheduleService.isLoadingFaculties else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVPNHint = true
                }
            }
        }
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
    @State private var showVPNHint = false
    @State private var vpnHintTask: Task<Void, Never>?

    private var filteredGroups: [Group] {
        scheduleService.filteredGroups(searchText: searchText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Группа", systemImage: "person.3.fill")
                .font(.headline)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Поиск группы...", text: $searchText)
                    .textFieldStyle(.roundedBorder)

                if !searchText.isEmpty {
                    Button("Очистить") { searchText = "" }
                        .font(.caption)
                        .foregroundColor(.blue)
                }
            }

            if scheduleService.isLoadingGroups {
                HStack {
                    Spacer()
                    VStack(spacing: 10) {
                        ProgressView("Загрузка групп...")
                        if showVPNHint {
                            MiniVPNHintBanner()
                                .frame(maxWidth: 340)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
            } else if filteredGroups.isEmpty {
                Text("Группы не найдены")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(filteredGroups) { group in
                        MiniGroupCard(
                            group: group,
                            isSelected: scheduleService.selectedGroup?.id == group.id
                        ) {
                            scheduleService.selectGroup(group)
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 8, x: 0, y: 4)
        )
        .onAppear {
            updateVPNHint(isLoading: scheduleService.isLoadingGroups)
        }
        .onChange(of: scheduleService.isLoadingGroups) { newValue in
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
            guard scheduleService.isLoadingGroups else { return }
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showVPNHint = true
                }
            }
        }
    }
}

private struct MiniGroupCard: View {
    let group: Group
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                Text(group.name)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(isSelected ? .white : .primary)
                    .lineLimit(1)

                Text(group.fullName)
                    .font(.caption)
                    .foregroundColor(isSelected ? .white.opacity(0.85) : .secondary)
                    .lineLimit(2)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 84, maxHeight: 96, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(isSelected ? Color.blue : Color(.systemGray6))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.blue.opacity(0.0) : Color(.systemGray4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
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

                Text(lesson.type.rawValue)
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
                            Text(lesson.type.rawValue)
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

private struct MiniFacultyMissingIdBanner: View {
    let missingNames: [String]

    var body: some View {
        guard !missingNames.isEmpty else { return AnyView(EmptyView()) }

        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Некоторые институты не отображаются")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                }

                Text("Сайт ДВГУПС не назначил им ID, поэтому App Clip не может загрузить по ним группы/расписание.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(missingNames.joined(separator: " • "))
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.orange.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                    )
            )
        )
    }
}

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
        switch rawValue.lowercased() {
        case "лекции": self = .lecture
        case "практика": self = .practice
        case "лабораторные работы": self = .laboratory
        default: self = .unknown
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
        onlineLink: String? = nil
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
    @Published var facultiesMissingIDs: [String] = []
    @Published var selectedFaculty: Faculty?
    @Published var groups: [Group] = []
    @Published var selectedGroup: Group?
    @Published var currentSchedule: Schedule?
    @Published var selectedDate: Date = Date()

    @Published var isLoadingFaculties = false
    @Published var isLoadingGroups = false
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
            facultiesMissingIDs = result.missingIdNames
            didLoadFaculties = true

            if selectedFaculty == nil {
                // restore from defaults or pick reasonable default
                let storedFacultyId = defaults.string(forKey: kFacultyId)
                if let storedFacultyId,
                   let restored = faculties.first(where: { $0.id == storedFacultyId }) {
                    selectedFaculty = restored
                } else {
                    selectedFaculty = faculties.first(where: { $0.id == "2" }) ?? faculties.first
                }
            } else if let selectedFaculty {
                self.selectedFaculty = faculties.first(where: { $0.id == selectedFaculty.id }) ?? selectedFaculty
            }

            if selectedFaculty != nil {
                await loadGroups()
            }
        } catch {
            facultiesMissingIDs = []
            didLoadFaculties = true
            errorMessage = error.localizedDescription
        }

        isLoadingFaculties = false
    }

    func loadGroups() async {
        guard let faculty = selectedFaculty else {
            errorMessage = "Факультет не выбран"
            return
        }

        isLoadingGroups = true
        errorMessage = nil

        do {
            let fetched = try await apiClient.fetchGroups(for: faculty.id)
            groups = fetched

            defaults.set(faculty.id, forKey: kFacultyId)

            // Try to restore group if already chosen
            let storedGroupId = defaults.string(forKey: kGroupId)
            if let storedGroupId,
               let restored = groups.first(where: { $0.id == storedGroupId }) {
                selectedGroup = restored
                await loadWeekSchedule()
            } else {
                selectedGroup = nil
                currentSchedule = nil
            }

            if fetched.isEmpty {
                errorMessage = "Группы для данного факультета не найдены"
            }
        } catch {
            groups = []
            errorMessage = error.localizedDescription
        }

        isLoadingGroups = false
    }

    func selectFaculty(_ faculty: Faculty) {
        selectedFaculty = faculty
        selectedGroup = nil
        currentSchedule = nil
        groups = []
        errorMessage = nil
        defaults.set(faculty.id, forKey: kFacultyId)
        defaults.removeObject(forKey: kGroupId)
        defaults.removeObject(forKey: kGroupName)

        Task { await loadGroups() }
    }

    func selectGroup(_ group: Group) {
        selectedGroup = group
        currentSchedule = nil
        errorMessage = nil
        defaults.set(group.id, forKey: kGroupId)
        defaults.set(group.name, forKey: kGroupName)

        Task { await loadWeekSchedule() }
    }

    func filteredGroups(searchText: String) -> [Group] {
        guard !searchText.isEmpty else { return groups }
        return groups.filter { g in
            g.name.localizedCaseInsensitiveContains(searchText) ||
            g.fullName.localizedCaseInsensitiveContains(searchText)
        }
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        Task { [selectedGroup] in
            if selectedGroup != nil {
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
        }
    }
}

@MainActor
final class DVGUPSAPIClient: ObservableObject {
    private let primaryBaseURL = URL(string: "https://next.dvgups.ru/ext/")!
    private let fallbackBaseURL = URL(string: "https://dvgups.ru/ext/")!

    private let session: URLSession

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

    func fetchGroups(for facultyId: String) async throws -> [Group] {
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
            .sorted { $0.name < $1.name }
    }

    func fetchSchedule(for groupId: String, startDate: Date = Date(), endDate: Date? = nil) async throws -> Schedule {
        let daysCount = Self.computeDaysCount(startDate: startDate, endDate: endDate)
        let startDateString = DateFormatter.serverDateFormatter.string(from: startDate)

        struct ScheduleItemDTO: Decodable {
            let startTime: String
            let endTime: String
            let date: String
            let lessonData: LessonDataDTO

            struct LessonDataDTO: Decodable {
                let courseType: CourseTypeDTO
                let courseSubject: CourseSubjectDTO
                let teacherList: [TeacherDTO]
                let studentList: [StudentDTO]
                let studyPlace: StudyPlaceDTO?

                struct CourseTypeDTO: Decodable {
                    let name: String
                    let nameAbbr: String?
                    enum CodingKeys: String, CodingKey { case name; case nameAbbr = "name_abbr" }
                }
                struct CourseSubjectDTO: Decodable {
                    let name: String
                    let nameAbbr: String?
                    enum CodingKeys: String, CodingKey { case name; case nameAbbr = "name_abbr" }
                }
                struct TeacherDTO: Decodable {
                    let name: String
                    let nameAbbr: String?
                    enum CodingKeys: String, CodingKey { case name; case nameAbbr = "name_abbr" }
                }
                struct StudentDTO: Decodable {
                    let name: String?
                    let nameAbbr: String?
                    let studentGroupName: String?
                    let studentGroupNameAbbr: String?

                    enum CodingKeys: String, CodingKey {
                        case name
                        case nameAbbr = "name_abbr"
                        case studentGroupName = "student_group_name"
                        case studentGroupNameAbbr = "student_group_name_abbr"
                    }
                }
                struct StudyPlaceDTO: Decodable {
                    let name: String
                    let ownerName: String?
                    enum CodingKeys: String, CodingKey { case name; case ownerName = "owner_name" }
                }

                enum CodingKeys: String, CodingKey {
                    case courseType = "course_type"
                    case courseSubject = "course_subject"
                    case teacherList = "teacher_list"
                    case studentList = "student_list"
                    case studyPlace = "study_place"
                }
            }

            enum CodingKeys: String, CodingKey {
                case startTime = "start_time"
                case endTime = "end_time"
                case date
                case lessonData = "lesson_data"
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
        var resolvedGroupName: String? = nil

        for item in response.data {
            guard let lessonDate = DateFormatter.serverDateFormatter.date(from: item.date) else {
                continue
            }

            if resolvedGroupName == nil {
                resolvedGroupName =
                    item.lessonData.studentList.first?.studentGroupNameAbbr ??
                    item.lessonData.studentList.first?.studentGroupName ??
                    item.lessonData.studentList.first?.nameAbbr ??
                    item.lessonData.studentList.first?.name
            }

            let timeStartHHmm = Self.hhmm(fromHHmmss: item.startTime)
            let timeEndHHmm = Self.hhmm(fromHHmmss: item.endTime)
            let pairNumber = Self.pairNumber(forStartTime: timeStartHHmm)

            let lessonType = LessonType(from: item.lessonData.courseType.name)
            let subject = item.lessonData.courseSubject.name

            let room = Self.composeRoom(
                name: item.lessonData.studyPlace?.name,
                ownerName: item.lessonData.studyPlace?.ownerName
            )

            let teacherName = item.lessonData.teacherList.first?.nameAbbr ?? item.lessonData.teacherList.first?.name
            let teacher: Teacher? = (teacherName?.isEmpty == false) ? Teacher(name: teacherName!) : nil

            let groups = item.lessonData.studentList
                .compactMap { $0.studentGroupNameAbbr ?? $0.studentGroupName ?? $0.nameAbbr }
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            let lesson = Lesson(
                pairNumber: pairNumber,
                timeStart: timeStartHHmm,
                timeEnd: timeEndHHmm,
                type: lessonType,
                subject: subject,
                room: room,
                teacher: teacher,
                groups: groups,
                onlineLink: nil
            )

            lessonsByDate[lessonDate, default: []].append(lesson)
        }

        let days: [ScheduleDay] = lessonsByDate
            .map { (date, lessons) in
                let weekday = DateFormatter.weekdayRuFormatter.string(from: date).capitalized
                return ScheduleDay(
                    date: date,
                    weekday: weekday,
                    lessons: lessons.sorted { lhs, rhs in
                        if lhs.pairNumber != rhs.pairNumber { return lhs.pairNumber < rhs.pairNumber }
                        return lhs.timeStart < rhs.timeStart
                    }
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
            guard shouldFallback(from: error) else { throw error }
            return try await performRequest(baseURL: fallbackBaseURL, path: path, queryItems: queryItems)
        }
    }

    private func performRequest<T: Decodable>(
        baseURL: URL,
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> T {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }

        components.queryItems = [
            URLQueryItem(name: "api", value: "1"),
            URLQueryItem(name: "path", value: path)
        ] + queryItems

        guard let url = components.url else { throw APIError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

            if (500...599).contains(http.statusCode), baseURL == primaryBaseURL {
                throw APIError.invalidResponse
            }
            guard (200...299).contains(http.statusCode) else {
                throw APIError.invalidResponse
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
                case .timedOut, .cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .dnsLookupFailed, .internationalRoamingOff:
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
            case .vpnOrBlockedNetwork, .invalidResponse:
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

    private static func hhmm(fromHHmmss value: String) -> String {
        if value.count >= 5 { return String(value.prefix(5)) }
        return value
    }

    private static func pairNumber(forStartTime hhmm: String) -> Int {
        func parse(_ s: String) -> (Int, Int)? {
            let parts = s.split(separator: ":")
            guard parts.count >= 2,
                  let h = Int(parts[0]),
                  let m = Int(parts[1]) else { return nil }
            return (h, m)
        }

        guard let target = parse(hhmm) else { return 0 }

        for t in LessonTime.schedule {
            if let start = parse(t.startTime), start == target {
                return t.number
            }
        }

        if hhmm.hasPrefix("0"), let alt = parse(String(hhmm.dropFirst())) {
            for t in LessonTime.schedule {
                if let start = parse(t.startTime), start == alt {
                    return t.number
                }
            }
        }

        return 0
    }

    private static func composeRoom(name: String?, ownerName: String?) -> String? {
        guard let name else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let owner = ownerName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let owner, !owner.isEmpty {
            return "\(trimmedName) • \(owner)"
        }
        return trimmedName.isEmpty ? nil : trimmedName
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
