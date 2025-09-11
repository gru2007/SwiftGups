import Foundation
import CloudKit
import SwiftData
import UIKit
import os.log

/// Сервис для синхронизации изображений через CloudKit Assets
@MainActor
class CloudKitImageService: ObservableObject {
    @Published var isUploading = false
    @Published var isDownloading = false
    @Published var syncProgress: Double = 0.0
    @Published var lastSyncError: Error?
    
    private let container = CKContainer.default()
    private var privateDatabase: CKDatabase {
        container.privateCloudDatabase
    }
    
    /// Загружает изображение в CloudKit как Asset
    func uploadImage(
        _ image: UIImage, 
        for homework: Homework,
        originalFilename: String = "",
        context: ModelContext
    ) async throws -> HomeworkAttachment {
        
        guard let imageData = image.jpegData(compressionQuality: 0.8) else {
            throw CloudKitImageError.invalidImageData
        }
        
        isUploading = true
        syncProgress = 0.0
        
        defer {
            Task { @MainActor in
                isUploading = false
                syncProgress = 0.0
            }
        }
        
        do {
            // Проверяем доступность CloudKit
            let accountStatus = try await container.accountStatus()
            guard accountStatus == .available else {
                throw CloudKitImageError.iCloudUnavailable
            }
            
            // Создаем временный файл для CKAsset
            let tempURL = createTemporaryFile(data: imageData, filename: originalFilename)
            let asset = CKAsset(fileURL: tempURL)
            
            // Создаем запись CloudKit для изображения
            let record = CKRecord(recordType: "HomeworkImage")
            record["homeworkId"] = homework.id.uuidString as NSString
            record["image"] = asset
            record["originalFilename"] = originalFilename as NSString
            record["fileSize"] = imageData.count as NSNumber
            record["mimeType"] = "image/jpeg" as NSString
            record["uploadedAt"] = Date() as NSDate
            
            syncProgress = 0.5
            
            // Загружаем в CloudKit
            let savedRecord = try await privateDatabase.save(record)
            
            syncProgress = 0.8
            
            // Создаем локальное вложение в SwiftData
            let attachment = HomeworkAttachment(
                id: savedRecord.recordID.recordName,
                homeworkId: homework.id.uuidString,
                type: .image,
                filename: "\(UUID().uuidString).jpg",
                originalFilename: originalFilename,
                fileSize: imageData.count,
                mimeType: "image/jpeg"
            )
            
            // Сохраняем локальную копию
            let localPath = await AttachmentManager.shared.saveImage(image, withFilename: attachment.filename)
            if let localPath = localPath {
                attachment.markAsDownloaded(localPath: localPath)
            }
            
            // Помечаем как загруженное в CloudKit
            if let assetURL = savedRecord["image"] as? CKAsset {
                attachment.markAsUploaded(cloudAssetURL: assetURL.fileURL?.absoluteString ?? "")
            }
            
            // Добавляем к домашнему заданию
            context.insert(attachment)
            homework.addCloudAttachment(attachment)
            
            syncProgress = 1.0
            
            // Очищаем временный файл
            try? FileManager.default.removeItem(at: tempURL)
            
            os_log("✅ Image uploaded to CloudKit successfully", log: .default, type: .info)
            
            return attachment
            
        } catch {
            lastSyncError = error
            os_log("❌ Failed to upload image to CloudKit: %@", log: .default, type: .error, error.localizedDescription)
            throw error
        }
    }
    
    /// Загружает изображение из CloudKit
    func downloadImage(attachment: HomeworkAttachment) async throws -> UIImage? {
        guard let cloudAssetURL = attachment.cloudAssetURL,
              !cloudAssetURL.isEmpty else {
            throw CloudKitImageError.noCloudAsset
        }
        
        isDownloading = true
        syncProgress = 0.0
        
        defer {
            Task { @MainActor in
                isDownloading = false
                syncProgress = 0.0
            }
        }
        
        do {
            // Получаем запись из CloudKit
            let recordID = CKRecord.ID(recordName: attachment.id)
            let record = try await privateDatabase.record(for: recordID)
            
            syncProgress = 0.3
            
            guard let asset = record["image"] as? CKAsset,
                  let assetURL = asset.fileURL else {
                throw CloudKitImageError.invalidAsset
            }
            
            syncProgress = 0.6
            
            // Загружаем данные изображения
            let imageData = try Data(contentsOf: assetURL)
            guard let image = UIImage(data: imageData) else {
                throw CloudKitImageError.invalidImageData
            }
            
            syncProgress = 0.9
            
            // Сохраняем локальную копию
            let localPath = await AttachmentManager.shared.saveImage(image, withFilename: attachment.filename)
            if let localPath = localPath {
                attachment.markAsDownloaded(localPath: localPath)
            }
            
            syncProgress = 1.0
            
            os_log("✅ Image downloaded from CloudKit successfully", log: .default, type: .info)
            
            return image
            
        } catch {
            lastSyncError = error
            attachment.syncStatus = .error
            os_log("❌ Failed to download image from CloudKit: %@", log: .default, type: .error, error.localizedDescription)
            throw error
        }
    }
    
    /// Синхронизирует все изображения домашнего задания
    func syncHomeworkImages(_ homework: Homework, context: ModelContext) async {
        os_log("🔄 Starting sync for homework images", log: .default, type: .info)
        
        var uploadCount = 0
        var downloadCount = 0
        
        // Загружаем локальные изображения в CloudKit
        for localAttachment in homework.imageAttachments {
            if let image = AttachmentManager.shared.loadImage(localAttachment) {
                do {
                    let _ = try await uploadImage(image, for: homework, originalFilename: localAttachment, context: context)
                    uploadCount += 1
                    
                    // Удаляем из локального списка после успешной загрузки в CloudKit
                    homework.removeAttachment(localAttachment)
                    AttachmentManager.shared.deleteAttachment(localAttachment)
                    
                } catch {
                    os_log("⚠️ Failed to upload local image %@: %@", log: .default, type: .info, localAttachment, error.localizedDescription)
                }
            }
        }
        
        // Загружаем CloudKit изображения локально
        if let cloudAttachments = homework.cloudAttachments {
            for cloudAttachment in cloudAttachments {
                if cloudAttachment.type == .image && !cloudAttachment.isDownloaded {
                    do {
                        let _ = try await downloadImage(attachment: cloudAttachment)
                        downloadCount += 1
                    } catch {
                        os_log("⚠️ Failed to download cloud image %@: %@", log: .default, type: .info, cloudAttachment.id, error.localizedDescription)
                    }
                }
            }
        }
        
        homework.lastImageSync = Date()
        
        os_log("✅ Homework image sync completed: %d uploaded, %d downloaded", log: .default, type: .info, uploadCount, downloadCount)
    }
    
    /// Удаляет изображение из CloudKit
    func deleteCloudImage(_ attachment: HomeworkAttachment) async throws {
        guard attachment.isUploaded else { return }
        
        do {
            let recordID = CKRecord.ID(recordName: attachment.id)
            try await privateDatabase.deleteRecord(withID: recordID)
            
            // Удаляем локальную копию
            if let localPath = attachment.localCachedPath {
                AttachmentManager.shared.deleteAttachment(localPath)
            }
            
            os_log("✅ Image deleted from CloudKit successfully", log: .default, type: .info)
            
        } catch {
            os_log("❌ Failed to delete image from CloudKit: %@", log: .default, type: .error, error.localizedDescription)
            throw error
        }
    }
    
    // MARK: - Private Helpers
    
    private func createTemporaryFile(data: Data, filename: String) -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let tempFilename = filename.isEmpty ? "\(UUID().uuidString).jpg" : filename
        let tempURL = tempDirectory.appendingPathComponent(tempFilename)
        
        do {
            try data.write(to: tempURL)
        } catch {
            os_log("❌ Failed to create temporary file: %@", log: .default, type: .error, error.localizedDescription)
        }
        
        return tempURL
    }
    
    /// Проверяет доступность CloudKit для синхронизации изображений
    func checkCloudKitAvailability() async -> Bool {
        do {
            let accountStatus = try await container.accountStatus()
            return accountStatus == .available
        } catch {
            return false
        }
    }
    
    /// Получает статистику синхронизации
    func getSyncStats(for homework: Homework) -> HomeworkSyncStats {
        let totalImages = homework.allImageAttachments.count
        let syncedImages = homework.cloudAttachments?.filter { $0.type == .image && $0.isUploaded }.count ?? 0
        let pendingImages = homework.imageAttachments.count // Локальные, не синхронизированные
        let errorImages = homework.cloudAttachments?.filter { $0.syncStatus == .error }.count ?? 0
        
        return HomeworkSyncStats(
            totalImages: totalImages,
            syncedImages: syncedImages,
            pendingImages: pendingImages,
            errorImages: errorImages,
            lastSync: homework.lastImageSync
        )
    }
}

// MARK: - Error Types

enum CloudKitImageError: Error, LocalizedError {
    case invalidImageData
    case iCloudUnavailable
    case noCloudAsset
    case invalidAsset
    case syncFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Не удалось обработать изображение"
        case .iCloudUnavailable:
            return "iCloud недоступен"
        case .noCloudAsset:
            return "Облачное изображение не найдено"
        case .invalidAsset:
            return "Поврежденное изображение в iCloud"
        case .syncFailed(let message):
            return "Ошибка синхронизации: \(message)"
        }
    }
}

// MARK: - Stats Types

struct HomeworkSyncStats {
    let totalImages: Int
    let syncedImages: Int
    let pendingImages: Int
    let errorImages: Int
    let lastSync: Date
    
    var isFullySynced: Bool {
        return pendingImages == 0 && errorImages == 0 && totalImages > 0
    }
    
    var syncPercentage: Double {
        guard totalImages > 0 else { return 1.0 }
        return Double(syncedImages) / Double(totalImages)
    }
}
