import SwiftUI
import SwiftData

// MARK: - Homework Views

struct AddHomeworkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var existingHomeworks: [Homework]
    
    @State private var title = ""
    @State private var subject = ""
    @State private var description = ""
    @State private var dueDate = Date()
    @State private var priority = HomeworkPriority.medium
    @State private var suggestedSubjects: [String] = []
    @State private var showSuggestions = false
    @State private var selectedImages: [UIImage] = []
    @State private var showingPhotoSelection = false
    @AppStorage("subjectPresets") private var subjectPresetsStorage: String = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section("Основная информация") {
                    TextField("Название задания", text: $title)
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Предмет", text: $subject)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .onChange(of: subject) { newValue in
                                updateSuggestions(for: newValue)
                            }
                            .onTapGesture {
                                if subject.isEmpty {
                                    updateSuggestions(for: "")
                                }
                            }
                        
                        if showSuggestions && !suggestedSubjects.isEmpty {
                            SubjectSuggestionsView(
                                subjects: suggestedSubjects,
                                onSelect: { selectedSubject in
                                    subject = selectedSubject
                                    showSuggestions = false
                                }
                            )
                        }
                    }
                }
                
                Section("Описание") {
                    TextField("Описание задания", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                }
                
                Section("Детали") {
                    DatePicker("Дата сдачи", selection: $dueDate, displayedComponents: [.date])
                    
                    Picker("Приоритет", selection: $priority) {
                        ForEach(HomeworkPriority.allCases, id: \.self) { priority in
                            Text(priority.rawValue).tag(priority)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                Section("Фотографии") {
                    PhotoAttachmentButton(
                        selectedImagesCount: selectedImages.count,
                        onTap: { showingPhotoSelection = true }
                    )
                }
            }
            .navigationTitle("Новое задание")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Отмена") { dismiss() }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Сохранить") {
                        saveHomework()
                    }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
                }
            }
        }
        .sheet(isPresented: $showingPhotoSelection) {
            PhotoSelectionSheet(showingSheet: $showingPhotoSelection, selectedImages: $selectedImages)
        }
    }
    
    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private func saveHomework() {
        let homework = Homework(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            dueDate: dueDate,
            priority: priority
        )
        
        // Сохраняем выбранные изображения
        for image in selectedImages {
            if let filename = AttachmentManager.shared.saveImage(image) {
                homework.addAttachment(filename)
            }
        }
        
        modelContext.insert(homework)
        
        do {
            try modelContext.save()
            persistSubjectPreset()
            
            // Автоматически синхронизируем изображения с iCloud
            if !selectedImages.isEmpty {
                Task {
                    let imageService = CloudKitImageService()
                    await imageService.syncHomeworkImages(homework, context: modelContext)
                }
            }
            
            dismiss()
        } catch {
            print("Error saving homework: \(error)")
        }
    }

    private func updateSuggestions(for text: String) {
        // Получаем предметы из существующих домашних заданий
        let existingSubjects = Set(existingHomeworks.map { $0.subject.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter { !$0.isEmpty }
        
        // Получаем сохраненные предметы
        let stored = subjectPresetsStorage.split(separator: "|").map { String($0) }
        
        // Базовые предметы
        let baseDefaults: [String] = [
            "Математика","Физика","Информатика","Экономика","История",
            "Английский язык","Программирование","Сети","Алгоритмы",
            "Базы данных","Операционные системы","ОП ИИ"
        ]
        
        // Объединяем все источники предметов
        let allSubjects = Array(Set(Array(existingSubjects) + stored + baseDefaults))
            .filter { !$0.isEmpty }
            .sorted()
        
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            suggestedSubjects = allSubjects
            showSuggestions = true
        } else {
            suggestedSubjects = allSubjects.filter { $0.localizedCaseInsensitiveContains(trimmed) }
            showSuggestions = !suggestedSubjects.isEmpty
        }
    }

    private func persistSubjectPreset() {
        let value = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        var existing = Set(subjectPresetsStorage.split(separator: "|").map { String($0) })
        existing.insert(value)
        subjectPresetsStorage = existing.sorted().joined(separator: "|")
    }
}

// MARK: - Supporting Components

struct SubjectSuggestionsView: View {
    let subjects: [String]
    let onSelect: (String) -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Предметы:")
                .font(.caption)
                .foregroundColor(.secondary)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 8) {
                ForEach(subjects.prefix(8), id: \.self) { item in
                    Button(action: { 
                        onSelect(item)
                        // Haptic feedback
                        let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                        impactFeedback.impactOccurred()
                    }) {
                        HStack {
                            Text(item)
                                .font(.subheadline)
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(.blue)
                                .font(.caption)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.blue.opacity(0.3), lineWidth: 1)
                                )
                        )
                    }
                }
            }
            
            if subjects.count > 8 {
                Text("И еще \(subjects.count - 8) предметов...")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5).opacity(0.3))
        )
    }
}

struct PhotoAttachmentButton: View {
    let selectedImagesCount: Int
    let onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundColor(.blue)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Добавить фото")
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text("Прикрепить фотографии к заданию")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if selectedImagesCount > 0 {
                    Text("\(selectedImagesCount)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
            )
        }
    }
}

struct HomeworkCard: View {
    let homework: Homework
    let toggleAction: () -> Void
    @State private var showingPhotos = false
    @State private var selectedImageAttachment: HomeworkImageAttachment?
    
    private var isOverdue: Bool {
        !homework.isCompleted && homework.dueDate < Date()
    }
    
    private var priorityColor: Color {
        switch homework.priority {
        case .low: return .gray
        case .medium: return .blue
        case .high: return .orange
        case .urgent: return .red
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(homework.title)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(homework.isCompleted ? .secondary : .primary)
                        .strikethrough(homework.isCompleted)
                    
                    Text(homework.subject)
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                
                Spacer()
                
                Button(action: {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    
                    withAnimation(.easeInOut(duration: 0.2)) {
                        toggleAction()
                    }
                }) {
                    Image(systemName: homework.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(homework.isCompleted ? .green : .gray)
                        .symbolEffect(.bounce, value: homework.isCompleted)
                }
                .buttonStyle(PlainButtonStyle())
                .frame(width: 44, height: 44)
            }
            
            if !homework.desc.isEmpty {
                Text(homework.desc)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
            }
            
            // Миниатюры фотографий (если есть)
            if !homework.allImageAttachments.isEmpty {
                EnhancedHomeworkImageThumbnails(
                    attachments: homework.allImageAttachments,
                    onShowPhotos: { showingPhotos = true },
                    onImageTap: { attachment in
                        selectedImageAttachment = attachment
                    }
                )
            }
            
            HStack {
                // Приоритет
                HStack(spacing: 4) {
                    Circle()
                        .fill(priorityColor)
                        .frame(width: 8, height: 8)
                    
                    Text(homework.priority.rawValue)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                // Иконка фотографий (если есть)
                if !homework.allImageAttachments.isEmpty {
                    Button {
                        showingPhotos = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "photo")
                                .font(.caption)
                                .foregroundColor(.blue)
                            
                            Text("\(homework.allImageAttachments.count)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.blue.opacity(0.1))
                        )
                    }
                }
                
                Spacer()
                
                // Дата сдачи
                Text(homework.dueDate, format: .dateTime.day().month().year())
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(isOverdue ? .red : .secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(isOverdue ? Color.red.opacity(0.3) : Color.clear, lineWidth: 1)
                )
        )
        .sheet(isPresented: $showingPhotos) {
            HomeworkPhotosSheet(homework: homework)
        }
        .sheet(isPresented: Binding(
            get: { selectedImageAttachment != nil },
            set: { _ in selectedImageAttachment = nil }
        )) {
            if let attachment = selectedImageAttachment {
                EnhancedImageViewerSheet(imageAttachment: attachment)
            }
        }
    }
}

struct HomeworkImageThumbnails: View {
    let attachments: [String]
    let onShowPhotos: () -> Void
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments.prefix(3), id: \.self) { attachment in
                    Button(action: onShowPhotos) {
                        if let image = AttachmentManager.shared.loadImage(attachment) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 40)
                                .clipped()
                                .cornerRadius(8)
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 60, height: 40)
                                .cornerRadius(8)
                                .overlay(
                                    Image(systemName: "photo")
                                        .foregroundColor(.gray)
                                )
                        }
                    }
                }
                
                // Показать "+X" если фотографий больше 3
                if attachments.count > 3 {
                    Button(action: onShowPhotos) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 60, height: 40)
                            .cornerRadius(8)
                            .overlay(
                                Text("+\(attachments.count - 3)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            )
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

struct EnhancedHomeworkImageThumbnails: View {
    let attachments: [HomeworkImageAttachment]
    let onShowPhotos: () -> Void
    let onImageTap: ((HomeworkImageAttachment) -> Void)?
    @StateObject private var attachmentManager = AttachmentManager.shared
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(attachments.prefix(3), id: \.id) { attachment in
                    Button(action: {
                        if let onImageTap = onImageTap {
                            onImageTap(attachment)
                        } else {
                            onShowPhotos()
                        }
                    }) {
                        EnhancedImageThumbnail(attachment: attachment)
                    }
                }
                
                // Показать "+X" если фотографий больше 3
                if attachments.count > 3 {
                    Button(action: onShowPhotos) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.1))
                            .frame(width: 60, height: 40)
                            .cornerRadius(8)
                            .overlay(
                                Text("+\(attachments.count - 3)")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.blue)
                            )
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

struct EnhancedImageThumbnail: View {
    let attachment: HomeworkImageAttachment
    @StateObject private var attachmentManager = AttachmentManager.shared
    @State private var image: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        ZStack {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 60, height: 40)
                    .clipped()
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(width: 60, height: 40)
                    .cornerRadius(8)
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.6)
                        } else {
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        }
                    }
            }
            
            // Индикатор синхронизации
            if attachment.type == .cloud, let cloudAttachment = attachment.cloudAttachment {
                VStack {
                    HStack {
                        Spacer()
                        Circle()
                            .fill(syncStatusColor(cloudAttachment.syncStatus))
                            .frame(width: 8, height: 8)
                    }
                    Spacer()
                }
                .padding(4)
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        isLoading = true
        do {
            self.image = try await attachmentManager.loadImage(from: attachment)
        } catch {
            print("Failed to load image: \(error)")
        }
        isLoading = false
    }
    
    private func syncStatusColor(_ status: AttachmentSyncStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .uploading: return .blue
        case .downloading: return .cyan
        case .synced: return .green
        case .error: return .red
        }
    }
}

struct HomeworkPhotosSheet: View {
    let homework: Homework
    @Environment(\.dismiss) private var dismiss
    @State private var selectedImageURL: URL?
    @State private var selectedImageAttachment: HomeworkImageAttachment?
    @State private var showingExportSheet = false
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(homework.allImageAttachments, id: \.id) { attachment in
                        EnhancedHomeworkImageGridItem(
                            attachment: attachment,
                            onTap: {
                                selectedImageAttachment = attachment
                            }
                        )
                    }
                }
                .padding()
            }
            .navigationTitle("Фотографии")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text(homework.title)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack {
                        Button {
                            showingExportSheet = true
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.title3)
                        }
                        
                        Button("Закрыть") {
                            dismiss()
                        }
                        .fontWeight(.semibold)
                    }
                }
            }
        }
        .sheet(item: Binding<IdentifiableURL?>(
            get: { selectedImageURL.map(IdentifiableURL.init) },
            set: { _ in selectedImageURL = nil }
        )) { identifiableURL in
            ImageViewerSheet(imageURL: identifiableURL.url)
        }
        .sheet(isPresented: Binding(
            get: { selectedImageAttachment != nil },
            set: { _ in selectedImageAttachment = nil }
        )) {
            if let attachment = selectedImageAttachment {
                EnhancedImageViewerSheet(imageAttachment: attachment)
            }
        }
        .sheet(isPresented: $showingExportSheet) {
            EnhancedPhotoExportSheet(imageAttachments: homework.allImageAttachments)
        }
    }
}

struct EnhancedHomeworkImageGridItem: View {
    let attachment: HomeworkImageAttachment
    let onTap: () -> Void
    @StateObject private var attachmentManager = AttachmentManager.shared
    @State private var image: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 120, height: 120)
                        .clipped()
                        .cornerRadius(12)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 120, height: 120)
                        .cornerRadius(12)
                        .overlay {
                            if isLoading {
                                ProgressView()
                            } else {
                                Image(systemName: "photo")
                                    .font(.title2)
                                    .foregroundColor(.gray)
                            }
                        }
                }
                
                // Индикатор синхронизации
                if attachment.type == .cloud, let cloudAttachment = attachment.cloudAttachment {
                    VStack {
                        HStack {
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(syncStatusColor(cloudAttachment.syncStatus))
                                    .frame(width: 8, height: 8)
                                
                                if cloudAttachment.syncStatus == .uploading {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                }
                            }
                            .padding(6)
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(12)
                        }
                        Spacer()
                    }
                    .padding(8)
                }
            }
        }
        .task {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        isLoading = true
        do {
            self.image = try await attachmentManager.loadImage(from: attachment)
        } catch {
            print("Failed to load image: \(error)")
        }
        isLoading = false
    }
    
    private func syncStatusColor(_ status: AttachmentSyncStatus) -> Color {
        switch status {
        case .pending: return .orange
        case .uploading: return .blue
        case .downloading: return .cyan
        case .synced: return .green
        case .error: return .red
        }
    }
}

struct EnhancedPhotoExportSheet: View {
    let imageAttachments: [HomeworkImageAttachment]
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @StateObject private var attachmentManager = AttachmentManager.shared
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Экспорт фотографий")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Выберите, куда экспортировать \(imageAttachments.count) фотографий:")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 16) {
                    Button {
                        Task { await exportToPhotos() }
                    } label: {
                        ExportOption(
                            title: "Сохранить в галерею",
                            subtitle: "Добавить фото в приложение \"Фото\"",
                            icon: "photo.on.rectangle.angled",
                            color: .blue
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button {
                        showingShareSheet = true
                    } label: {
                        ExportOption(
                            title: "Поделиться",
                            subtitle: "Отправить в другие приложения",
                            icon: "square.and.arrow.up",
                            color: .green
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Экспорт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            EnhancedShareSheet(imageAttachments: imageAttachments)
        }
    }
    
    private func exportToPhotos() async {
        for attachment in imageAttachments {
            do {
                if let image = try await attachmentManager.loadImage(from: attachment) {
                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                }
            } catch {
                print("Failed to load image for export: \(error)")
            }
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
        }
    }
}

struct PhotoExportSheet: View {
    let imageAttachments: [String]
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("Экспорт фотографий")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Выберите, куда экспортировать \(imageAttachments.count) фотографий:")
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                
                VStack(spacing: 16) {
                    Button {
                        exportToPhotos()
                    } label: {
                        ExportOption(
                            title: "Сохранить в галерею",
                            subtitle: "Добавить фото в приложение \"Фото\"",
                            icon: "photo.on.rectangle.angled",
                            color: .blue
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    
                    Button {
                        showingShareSheet = true
                    } label: {
                        ExportOption(
                            title: "Поделиться",
                            subtitle: "Отправить в другие приложения",
                            icon: "square.and.arrow.up",
                            color: .green
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.horizontal)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Экспорт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Отмена") {
                        dismiss()
                    }
                }
            }
        }
        .sheet(isPresented: $showingShareSheet) {
            ShareSheet(items: imageAttachments.compactMap { AttachmentManager.shared.loadImage($0) })
        }
    }
    
    private func exportToPhotos() {
        let images = imageAttachments.compactMap { AttachmentManager.shared.loadImage($0) }
        
        for image in images {
            UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
        }
    }
}

struct ExportOption: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(color)
                .cornerRadius(10)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        
        // Настройка для iPad
        if let popover = controller.popoverPresentationController {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}

struct EnhancedShareSheet: UIViewControllerRepresentable {
    let imageAttachments: [HomeworkImageAttachment]
    @StateObject private var attachmentManager = AttachmentManager.shared
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        // Загружаем изображения синхронно для UIActivityViewController
        let images = loadImagesSync()
        let controller = UIActivityViewController(activityItems: images, applicationActivities: nil)
        
        // Настройка для iPad
        if let popover = controller.popoverPresentationController {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first {
                popover.sourceView = window
                popover.sourceRect = CGRect(x: window.bounds.midX, y: window.bounds.midY, width: 0, height: 0)
                popover.permittedArrowDirections = []
            }
        }
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
    
    private func loadImagesSync() -> [UIImage] {
        var images: [UIImage] = []
        
        for attachment in imageAttachments {
            switch attachment.type {
            case .local:
                if let path = attachment.localPath,
                   let image = AttachmentManager.shared.loadImage(path) {
                    images.append(image)
                }
            case .cloud:
                if let cloudAttachment = attachment.cloudAttachment,
                   let cachedPath = cloudAttachment.localCachedPath,
                   let image = AttachmentManager.shared.loadImage(cachedPath) {
                    images.append(image)
                }
            }
        }
        
        return images
    }
}

struct EmptyHomeworkView: View {
    let filter: HomeworkFilter
    
    private var emptyMessage: String {
        switch filter {
        case .all:
            return "У вас пока нет домашних заданий"
        case .pending:
            return "Нет заданий к выполнению"
        case .completed:
            return "Нет выполненных заданий"
        case .overdue:
            return "Нет просроченных заданий"
        }
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "book.closed")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.5))
            
            Text(emptyMessage)
                .font(.headline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            if filter == .all {
                Text("Нажмите «+» чтобы добавить первое задание")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
    }
}

enum HomeworkFilter: String, CaseIterable {
    case all = "Все"
    case pending = "К выполнению"
    case completed = "Выполненные"
    case overdue = "Просроченные"
    
    var icon: String {
        switch self {
        case .all: return "list.bullet"
        case .pending: return "clock"
        case .completed: return "checkmark.circle"
        case .overdue: return "exclamationmark.triangle"
        }
    }
}

struct HomeworkFilterBar: View {
    @Binding var selectedFilter: HomeworkFilter
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(HomeworkFilter.allCases, id: \.self) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: filter.icon)
                                .font(.caption)
                            
                            Text(filter.rawValue)
                                .font(.caption)
                                .fontWeight(.medium)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(selectedFilter == filter ? Color.blue : Color(.systemGray6))
                        )
                        .foregroundColor(selectedFilter == filter ? .white : .primary)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
}
