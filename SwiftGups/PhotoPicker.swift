//
//  PhotoPicker.swift
//  SwiftGups
//
//  Created by Assistant on 25.08.2025.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - Enhanced File Manager для работы с вложениями и CloudKit синхронизацией

@MainActor
class AttachmentManager: ObservableObject {
    static let shared = AttachmentManager()
    
    @Published var isProcessing = false
    @Published var syncProgress: Double = 0.0
    
    private init() {}
    
    /// Получаем папку для сохранения вложений
    private var attachmentsDirectory: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let attachmentsURL = documentsDirectory.appendingPathComponent("HomeworkAttachments")
        
        // Создаем папку если не существует
        if !FileManager.default.fileExists(atPath: attachmentsURL.path) {
            try? FileManager.default.createDirectory(at: attachmentsURL, withIntermediateDirectories: true)
        }
        
        return attachmentsURL
    }
    
    /// Получаем папку для кэша CloudKit изображений
    private var cloudCacheDirectory: URL {
        let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let cacheURL = documentsDirectory.appendingPathComponent("CloudKitImageCache")
        
        // Создаем папку если не существует
        if !FileManager.default.fileExists(atPath: cacheURL.path) {
            try? FileManager.default.createDirectory(at: cacheURL, withIntermediateDirectories: true)
        }
        
        return cacheURL
    }
    
    /// Сохраняем UIImage в локальное хранилище (обратная совместимость)
    func saveImage(_ image: UIImage) -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = attachmentsDirectory.appendingPathComponent(filename)
        
        do {
            try imageData.write(to: fileURL)
            return filename
        } catch {
            print("❌ Ошибка сохранения изображения: \(error)")
            return nil
        }
    }
    
    /// Сохраняем UIImage с указанным именем файла
    func saveImage(_ image: UIImage, withFilename filename: String?) async -> String? {
        await MainActor.run {
            isProcessing = true
            syncProgress = 0.0
        }
        
        defer {
            Task { @MainActor in
                isProcessing = false
                syncProgress = 0.0
            }
        }
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        
        let finalFilename = filename ?? "\(UUID().uuidString).jpg"
        let fileURL = attachmentsDirectory.appendingPathComponent(finalFilename)
        
        await MainActor.run { syncProgress = 0.5 }
        
        do {
            try imageData.write(to: fileURL)
            await MainActor.run { syncProgress = 1.0 }
            return finalFilename // Возвращаем только имя файла, не полный путь
        } catch {
            print("❌ Ошибка сохранения изображения: \(error)")
            return nil
        }
    }
    
    /// Сохраняем изображение в CloudKit кэш
    func saveImageToCache(_ image: UIImage, withFilename filename: String) async -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        
        let fileURL = cloudCacheDirectory.appendingPathComponent(filename)
        
        do {
            try imageData.write(to: fileURL)
            return filename
        } catch {
            print("❌ Ошибка сохранения изображения в кэш: \(error)")
            return nil
        }
    }
    
    /// Получаем UIImage по имени файла (проверяет оба хранилища)
    func loadImage(_ filename: String) -> UIImage? {
        // Сначала проверяем основное хранилище
        let mainFileURL = attachmentsDirectory.appendingPathComponent(filename)
        if let image = UIImage(contentsOfFile: mainFileURL.path) {
            return image
        }
        
        // Затем проверяем кэш CloudKit
        let cacheFileURL = cloudCacheDirectory.appendingPathComponent(filename)
        if let image = UIImage(contentsOfFile: cacheFileURL.path) {
            return image
        }
        
        return nil
    }
    
    /// Загружает изображение из HomeworkImageAttachment
    func loadImage(from attachment: HomeworkImageAttachment) async -> UIImage? {
        switch attachment.type {
        case .local:
            if let localPath = attachment.localPath {
                return loadImage(localPath)
            }
            return nil
            
        case .cloud:
            // Сначала пробуем загрузить из локального кэша
            if let cloudAttachment = attachment.cloudAttachment,
               let cachedPath = cloudAttachment.localCachedPath,
               cloudAttachment.isDownloaded {
                if let image = loadImage(cachedPath) {
                    return image
                }
            }
            
            // Если нет в кэше, загружаем из CloudKit
            if let cloudAttachment = attachment.cloudAttachment {
                let imageService = CloudKitImageService()
                do {
                    return try await imageService.downloadImage(attachment: cloudAttachment)
                } catch {
                    print("❌ Ошибка загрузки изображения из CloudKit: \(error)")
                    return nil
                }
            }
            
            return nil
        }
    }
    
    /// Удаляем файл из всех хранилищ
    func deleteAttachment(_ filename: String) {
        // Удаляем из основного хранилища
        let mainFileURL = attachmentsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: mainFileURL)
        
        // Удаляем из кэша
        let cacheFileURL = cloudCacheDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: cacheFileURL)
    }
    
    /// Получаем URL файла (проверяет оба хранилища)
    func getFileURL(_ filename: String) -> URL {
        let mainFileURL = attachmentsDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: mainFileURL.path) {
            return mainFileURL
        }
        
        let cacheFileURL = cloudCacheDirectory.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: cacheFileURL.path) {
            return cacheFileURL
        }
        
        // Возвращаем основной путь по умолчанию
        return mainFileURL
    }
    
    /// Получаем размер всех сохраненных изображений
    func getTotalStorageSize() -> Int64 {
        var totalSize: Int64 = 0
        
        // Размер основного хранилища
        if let files = try? FileManager.default.contentsOfDirectory(at: attachmentsDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for fileURL in files {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        
        // Размер кэша CloudKit
        if let files = try? FileManager.default.contentsOfDirectory(at: cloudCacheDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for fileURL in files {
                if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                    totalSize += Int64(fileSize)
                }
            }
        }
        
        return totalSize
    }
    
    /// Очищает старые файлы кэша (старше 30 дней)
    func cleanupOldCache() async {
        let calendar = Calendar.current
        let cutoffDate = calendar.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        await MainActor.run {
            isProcessing = true
        }
        
        defer {
            Task { @MainActor in
                isProcessing = false
            }
        }
        
        if let files = try? FileManager.default.contentsOfDirectory(at: cloudCacheDirectory, includingPropertiesForKeys: [.creationDateKey]) {
            for fileURL in files {
                if let creationDate = try? fileURL.resourceValues(forKeys: [.creationDateKey]).creationDate,
                   creationDate < cutoffDate {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }
        }
    }
    
    /// Форматирует размер файла для отображения
    static func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

// MARK: - Photo Picker

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Environment(\.dismiss) private var dismiss
    let sourceType: UIImagePickerController.SourceType
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.delegate = context.coordinator
        picker.sourceType = sourceType
        picker.allowsEditing = false
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: PhotoPicker
        
        init(parent: PhotoPicker) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.selectedImages.append(image)
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Photos UI Picker (для выбора нескольких фото из галереи)

struct MultiplePhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 5 // Максимум 5 фотографий
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MultiplePhotoPicker
        
        init(parent: MultiplePhotoPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            parent.dismiss()
            
            for result in results {
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                        if let image = image as? UIImage {
                            DispatchQueue.main.async {
                                self.parent.selectedImages.append(image)
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Enhanced Photo Selection Action Sheet

struct EnhancedPhotoSelectionSheet: View {
    let homework: Homework
    @Binding var showingSheet: Bool
    @State private var selectedImages: [UIImage] = []
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    @State private var isUploading = false
    @StateObject private var imageService = CloudKitImageService()
    @StateObject private var attachmentManager = AttachmentManager.shared
    @Environment(\.modelContext) private var modelContext
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 40))
                    .foregroundColor(.blue)
                
                Text("Добавить фотографии")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text("Автоматически синхронизируются с iCloud")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top)
            
            // Action buttons
            VStack(spacing: 16) {
                // Camera button
                Button {
                    showingCamera = true
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.blue.opacity(0.1))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Сделать фото")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("Сфотографируйте прямо сейчас")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .strokeBorder(Color(.systemGray5), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
                
                // Gallery button
                Button {
                    showingPhotoPicker = true
                } label: {
                    HStack(spacing: 16) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(.green.opacity(0.1))
                                .frame(width: 50, height: 50)
                            
                            Image(systemName: "photo.on.rectangle")
                                .font(.title2)
                                .foregroundColor(.green)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Выбрать из галереи")
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text("Выберите до 5 фотографий")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "chevron.right")
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground))
                            .strokeBorder(Color(.systemGray5), lineWidth: 1)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(.horizontal)
            
            // Upload progress
            if isUploading || !selectedImages.isEmpty {
                VStack(spacing: 12) {
                    if isUploading {
                        VStack(spacing: 8) {
                            ProgressView(value: imageService.syncProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                            
                            Text("Загрузка в iCloud... (\(Int(imageService.syncProgress * 100))%)")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal)
                    }
                    
                    // Selected images preview
                    if !selectedImages.isEmpty && !isUploading {
                        VStack(spacing: 8) {
                            Text("Выбрано изображений: \(selectedImages.count)")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(Array(selectedImages.enumerated()), id: \.offset) { index, image in
                                        Image(uiImage: image)
                                            .resizable()
                                            .aspectRatio(contentMode: .fill)
                                            .frame(width: 60, height: 60)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(Color.blue, lineWidth: 2)
                                            )
                                    }
                                }
                                .padding(.horizontal)
                            }
                            
                            // Upload button
                            Button(action: uploadSelectedImages) {
                                HStack {
                                    Image(systemName: "icloud.and.arrow.up")
                                        .font(.headline)
                                    Text("Загрузить в iCloud")
                                        .font(.headline)
                                }
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .cornerRadius(12)
                            }
                            .padding(.horizontal)
                            .disabled(isUploading)
                        }
                    }
                }
            }
            
            // Cancel button
            Button("Отмена") {
                selectedImages.removeAll()
                showingSheet = false
            }
            .font(.headline)
            .foregroundColor(.secondary)
            .padding(.bottom)
            .disabled(isUploading)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingCamera) {
            PhotoPicker(selectedImages: $selectedImages, sourceType: .camera)
        }
        .sheet(isPresented: $showingPhotoPicker) {
            MultiplePhotoPicker(selectedImages: $selectedImages)
        }
    }
    
    private func uploadSelectedImages() {
        guard !selectedImages.isEmpty else { return }
        
        isUploading = true
        
        Task {
            for (index, image) in selectedImages.enumerated() {
                do {
                    let originalFilename = "image_\(Date().timeIntervalSince1970)_\(index + 1).jpg"
                    let _ = try await imageService.uploadImage(
                        image, 
                        for: homework, 
                        originalFilename: originalFilename,
                        context: modelContext
                    )
                } catch {
                    print("❌ Ошибка загрузки изображения \(index + 1): \(error)")
                }
            }
            
            await MainActor.run {
                selectedImages.removeAll()
                isUploading = false
                showingSheet = false
            }
        }
    }
}

// MARK: - Legacy Photo Selection Action Sheet

struct PhotoSelectionSheet: View {
    @Binding var showingSheet: Bool
    @Binding var selectedImages: [UIImage]
    @State private var showingCamera = false
    @State private var showingPhotoPicker = false
    
    var body: some View {
        VStack(spacing: 20) {
            Text("Добавить фотографию")
                .font(.title2)
                .fontWeight(.semibold)
                .padding(.top)
            
            VStack(spacing: 16) {
                // Камера
                Button {
                    showingCamera = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        Text("Сделать фото")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.blue)
                    )
                }
                
                // Галерея
                Button {
                    showingPhotoPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.title2)
                            .foregroundColor(.white)
                        
                        Text("Выбрать из галереи")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Spacer()
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.green)
                    )
                }
            }
            .padding(.horizontal)
            
            Button("Отмена") {
                showingSheet = false
            }
            .font(.headline)
            .foregroundColor(.secondary)
            .padding(.bottom)
        }
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .sheet(isPresented: $showingCamera) {
            PhotoPicker(selectedImages: $selectedImages, sourceType: .camera)
        }
        .sheet(isPresented: $showingPhotoPicker) {
            MultiplePhotoPicker(selectedImages: $selectedImages)
        }
    }
}

// MARK: - Enhanced Attachment Display View

struct AttachmentsView: View {
    let homework: Homework
    let onDeleteAttachment: (HomeworkImageAttachment) -> Void
    @State private var selectedImage: HomeworkImageAttachment?
    @StateObject private var imageService = CloudKitImageService()
    @StateObject private var attachmentManager = AttachmentManager.shared
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        let allImages = homework.allImageAttachments
        
        if !allImages.isEmpty {
            VStack(alignment: .leading, spacing: 16) {
                // Header with sync status
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Прикрепленные фото (\(allImages.count))")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                        
                        // Sync status
                        let syncStats = imageService.getSyncStats(for: homework)
                        if syncStats.totalImages > 0 {
                            HStack(spacing: 8) {
                                if syncStats.isFullySynced {
                                    Image(systemName: "icloud.and.arrow.up")
                                        .foregroundColor(.green)
                                    Text("Синхронизировано")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else if syncStats.pendingImages > 0 {
                                    Image(systemName: "icloud.and.arrow.up")
                                        .foregroundColor(.orange)
                                    Text("\(syncStats.pendingImages) ожидают синхронизации")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                } else if syncStats.errorImages > 0 {
                                    Image(systemName: "exclamationmark.icloud")
                                        .foregroundColor(.red)
                                    Text("Ошибка синхронизации")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    // Sync button
                    if !imageService.isUploading && !imageService.isDownloading {
                        Button(action: {
                            Task {
                                await imageService.syncHomeworkImages(homework, context: homework.modelContext!)
                            }
                        }) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.title3)
                                .foregroundColor(.blue)
                        }
                    } else {
                        ProgressView()
                            .scaleEffect(0.8)
                    }
                }
                
                // Progress bar during sync
                if imageService.isUploading || imageService.isDownloading {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: imageService.syncProgress)
                            .progressViewStyle(LinearProgressViewStyle(tint: .blue))
                        Text(imageService.isUploading ? "Загрузка в iCloud..." : "Загрузка из iCloud...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Images grid
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(allImages) { imageAttachment in
                        EnhancedAttachmentThumbnail(
                            imageAttachment: imageAttachment,
                            onTap: {
                                selectedImage = imageAttachment
                            },
                            onDelete: {
                                onDeleteAttachment(imageAttachment)
                            }
                        )
                    }
                }
                
                // Storage info
                if allImages.count > 5 {
                    HStack {
                        Spacer()
                        Text("Занято: \(AttachmentManager.formatFileSize(attachmentManager.getTotalStorageSize()))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .sheet(item: $selectedImage) { imageAttachment in
                EnhancedImageViewerSheet(imageAttachment: imageAttachment)
            }
        }
    }
}

// Legacy support for existing code
struct LegacyAttachmentsView: View {
    let attachments: [String]
    let onDeleteAttachment: (String) -> Void
    @State private var selectedImageURL: URL?
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        if !attachments.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Прикрепленные фото (\(attachments.count))")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.secondary)
                
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(attachments, id: \.self) { attachment in
                        AttachmentThumbnail(
                            attachment: attachment,
                            onTap: {
                                selectedImageURL = AttachmentManager.shared.getFileURL(attachment)
                            },
                            onDelete: {
                                onDeleteAttachment(attachment)
                            }
                        )
                    }
                }
            }
            .sheet(item: Binding<IdentifiableURL?>(
                get: { selectedImageURL.map(IdentifiableURL.init) },
                set: { _ in selectedImageURL = nil }
            )) { identifiableURL in
                ImageViewerSheet(imageURL: identifiableURL.url)
            }
        }
    }
}

// MARK: - Attachment Thumbnail

struct AttachmentThumbnail: View {
    let attachment: String
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var image: UIImage?
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Изображение
            SwiftUI.Group {
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(width: 100, height: 100)
                        .cornerRadius(8)
                        .overlay(
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                        )
                }
            }
            .onTapGesture {
                onTap()
            }
            
            // Кнопка удаления
            Button {
                // Haptic feedback
                let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                impactFeedback.impactOccurred()
                
                // Удаляем файл и из модели
                AttachmentManager.shared.deleteAttachment(attachment)
                onDelete()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.white)
                    .background(Color.red, in: Circle())
            }
            .offset(x: 8, y: -8)
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        image = AttachmentManager.shared.loadImage(attachment)
    }
}

// MARK: - Enhanced Attachment Thumbnail

struct EnhancedAttachmentThumbnail: View {
    let imageAttachment: HomeworkImageAttachment
    let onTap: () -> Void
    let onDelete: () -> Void
    @State private var image: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main image container
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(width: 100, height: 100)
                .overlay(
                    SwiftUI.Group {
                        if let image = image {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        } else if isLoading {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle())
                        } else {
                            VStack(spacing: 4) {
                                Image(systemName: "photo")
                                    .foregroundColor(.gray)
                                    .font(.title2)
                                Text("Загрузка...")
                                    .font(.caption2)
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                )
                .onTapGesture {
                    onTap()
                }
            
            // Status indicators
            VStack(alignment: .trailing, spacing: 4) {
                // Sync status indicator
                if imageAttachment.type == .cloud {
                    let syncStatus = imageAttachment.syncStatus
                    let statusColor: Color = {
                        switch syncStatus {
                        case .synced: return .green
                        case .pending: return .orange
                        case .uploading, .downloading: return .blue
                        case .error: return .red
                        }
                    }()
                    
                    let statusIcon: String = {
                        switch syncStatus {
                        case .synced: return "icloud.and.arrow.up"
                        case .pending: return "icloud.and.arrow.up.fill"
                        case .uploading: return "icloud.and.arrow.up.fill"
                        case .downloading: return "icloud.and.arrow.down.fill"
                        case .error: return "exclamationmark.icloud"
                        }
                    }()
                    
                    Image(systemName: statusIcon)
                        .font(.caption)
                        .foregroundColor(.white)
                        .padding(4)
                        .background(statusColor, in: Circle())
                }
                
                // Delete button
                Button {
                    let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
                    impactFeedback.impactOccurred()
                    onDelete()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                        .background(Color.red, in: Circle())
                }
            }
            .offset(x: 8, y: -8)
        }
        .onAppear {
            loadImage()
        }
        .onChange(of: imageAttachment.id) { _ in
            loadImage()
        }
    }
    
    private func loadImage() {
        isLoading = true
        
        Task {
            let loadedImage = await AttachmentManager.shared.loadImage(from: imageAttachment)
            
            await MainActor.run {
                self.image = loadedImage
                self.isLoading = false
            }
        }
    }
}

// MARK: - Enhanced Image Viewer Sheet

struct EnhancedImageViewerSheet: View {
    let imageAttachment: HomeworkImageAttachment
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var image: UIImage?
    @State private var isLoading = false
    @GestureState private var magnifyBy = CGFloat(1.0)
    @GestureState private var panBy = CGSize.zero
    
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    
    var magnification: some Gesture {
        MagnificationGesture()
            .updating($magnifyBy) { currentState, gestureState, _ in
                gestureState = currentState
            }
            .onChanged { value in
                let newScale = lastScale * value
                scale = max(minScale, min(maxScale, newScale))
            }
            .onEnded { value in
                lastScale = scale
                
                // Если масштаб меньше минимального, возвращаем к 1
                if scale < minScale {
                    withAnimation(.spring()) {
                        scale = minScale
                        offset = .zero
                        lastScale = minScale
                        lastOffset = .zero
                    }
                }
            }
    }
    
    var drag: some Gesture {
        DragGesture()
            .updating($panBy) { currentState, gestureState, _ in
                gestureState = currentState.translation
            }
            .onChanged { value in
                let newOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = newOffset
            }
            .onEnded { value in
                lastOffset = offset
                
                // Возвращаем изображение в границы при увеличении
                if scale <= 1.0 {
                    withAnimation(.spring()) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale * magnifyBy)
                        .offset(
                            x: offset.width + panBy.width,
                            y: offset.height + panBy.height
                        )
                        .gesture(
                            ExclusiveGesture(magnification, drag)
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                if scale > minScale {
                                    // Возвращаем к исходному размеру
                                    scale = minScale
                                    offset = .zero
                                    lastScale = minScale
                                    lastOffset = .zero
                                } else {
                                    // Увеличиваем в 2 раза
                                    scale = 2.0
                                    lastScale = 2.0
                                }
                            }
                        }
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: scale)
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: offset)
                        
                } else if isLoading {
                    VStack(spacing: 16) {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                        
                        Text("Загрузка изображения...")
                            .foregroundColor(.white)
                            .font(.headline)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "photo")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        
                        Text("Не удалось загрузить изображение")
                            .foregroundColor(.gray)
                            .font(.headline)
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(imageAttachment.displayName)
                            .foregroundColor(.white)
                            .font(.headline)
                        
                        if imageAttachment.type == .cloud {
                            HStack(spacing: 4) {
                                Image(systemName: imageAttachment.isCloudSynced ? "icloud" : "icloud.slash")
                                    .font(.caption)
                                Text(imageAttachment.isCloudSynced ? "iCloud" : "Локально")
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        guard image == nil else { return }
        
        isLoading = true
        
        Task {
            let loadedImage = await AttachmentManager.shared.loadImage(from: imageAttachment)
            
            await MainActor.run {
                self.image = loadedImage
                self.isLoading = false
            }
        }
    }
}

// MARK: - Legacy Image Viewer Sheet

struct ImageViewerSheet: View {
    let imageURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var image: UIImage?
    @GestureState private var magnifyBy = CGFloat(1.0)
    @GestureState private var panBy = CGSize.zero
    
    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    
    var magnification: some Gesture {
        MagnificationGesture()
            .updating($magnifyBy) { currentState, gestureState, _ in
                gestureState = currentState
            }
            .onChanged { value in
                let newScale = lastScale * value
                scale = max(minScale, min(maxScale, newScale))
            }
            .onEnded { value in
                lastScale = scale
                
                if scale < minScale {
                    withAnimation(.spring()) {
                        scale = minScale
                        offset = .zero
                        lastScale = minScale
                        lastOffset = .zero
                    }
                }
            }
    }
    
    var drag: some Gesture {
        DragGesture()
            .updating($panBy) { currentState, gestureState, _ in
                gestureState = currentState.translation
            }
            .onChanged { value in
                let newOffset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = newOffset
            }
            .onEnded { value in
                lastOffset = offset
                
                if scale <= 1.0 {
                    withAnimation(.spring()) {
                        offset = .zero
                        lastOffset = .zero
                    }
                }
            }
    }
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale * magnifyBy)
                        .offset(
                            x: offset.width + panBy.width,
                            y: offset.height + panBy.height
                        )
                        .gesture(
                            ExclusiveGesture(magnification, drag)
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                                if scale > minScale {
                                    scale = minScale
                                offset = .zero
                                    lastScale = minScale
                                    lastOffset = .zero
                                } else {
                                    scale = 2.0
                                    lastScale = 2.0
                                }
                            }
                        }
                } else {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Закрыть") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .fontWeight(.semibold)
                }
            }
        }
        .onAppear {
            loadImage()
        }
    }
    
    private func loadImage() {
        image = UIImage(contentsOfFile: imageURL.path)
    }
}

// MARK: - Helper Types

struct IdentifiableURL: Identifiable {
    let id = UUID()
    let url: URL
}

