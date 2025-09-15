//
//  PhotoPicker.swift
//  SwiftGups
//
//  Created by Assistant on 25.08.2025.
//

import SwiftUI
import PhotosUI
import UIKit

// MARK: - File Manager для работы с вложениями

class AttachmentManager {
    static let shared = AttachmentManager()
    
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
    
    /// Сохраняем UIImage в локальное хранилище
    func saveImage(_ image: UIImage) -> String? {
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            return nil
        }
        
        let filename = "\(UUID().uuidString).jpg"
        let fileURL = attachmentsDirectory.appendingPathComponent(filename)
        
        do {
            try imageData.write(to: fileURL)
            return filename // Возвращаем только имя файла, не полный путь
        } catch {
            print("❌ Ошибка сохранения изображения: \(error)")
            return nil
        }
    }
    
    /// Получаем UIImage по имени файла
    func loadImage(_ filename: String) -> UIImage? {
        let fileURL = attachmentsDirectory.appendingPathComponent(filename)
        return UIImage(contentsOfFile: fileURL.path)
    }
    
    /// Удаляем файл
    func deleteAttachment(_ filename: String) {
        let fileURL = attachmentsDirectory.appendingPathComponent(filename)
        try? FileManager.default.removeItem(at: fileURL)
    }
    
    /// Получаем URL файла
    func getFileURL(_ filename: String) -> URL {
        return attachmentsDirectory.appendingPathComponent(filename)
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

// MARK: - Photo Selection Action Sheet

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

// MARK: - Attachment Display View

struct AttachmentsView: View {
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

// MARK: - Image Viewer Sheet

struct ImageViewerSheet: View {
    let imageURL: URL
    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var image: UIImage?
    
    var body: some View {
        NavigationView {
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let image = image {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaleEffect(scale)
                        .offset(offset)
                        .gesture(
                            SimultaneousGesture(
                                MagnificationGesture()
                                    .onChanged { value in
                                        scale = max(1.0, min(value, 4.0))
                                    },
                                DragGesture()
                                    .onChanged { value in
                                        offset = value.translation
                                    }
                                    .onEnded { _ in
                                        withAnimation {
                                            offset = .zero
                                        }
                                    }
                            )
                        )
                        .onTapGesture(count: 2) {
                            withAnimation {
                                scale = scale > 1 ? 1 : 2
                                offset = .zero
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

